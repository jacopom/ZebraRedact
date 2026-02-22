#!/usr/bin/env python3
"""
ZebraRedact Accuracy Evaluation Suite
======================================
Runs three redaction modes on diverse real-world texts and evaluates:

  • Detection recall  — what fraction of known PII was actually hidden
  • Leakage           — what private info remains inferable after redaction
  • Semantic quality  — does the text remain useful for its intended purpose

Modes tested
────────────
  token     → structural placeholders: [NAME_1], [EMAIL_1] …
  fake      → realistic synthetic replacements from fixed pools
  ai        → Claude-powered context-aware redaction

Usage
─────
  export ANTHROPIC_API_KEY=sk-ant-…
  python3 eval/redaction_eval.py
  python3 eval/redaction_eval.py --mode token        # single mode
  python3 eval/redaction_eval.py --case "Medical"    # single test case (substring match)
  python3 eval/redaction_eval.py --json              # machine-readable output
"""

import re
import sys
import os
import json
import time
import argparse
import textwrap
import urllib.request
from dataclasses import dataclass, field
from typing import Optional
import anthropic

# ─── .env loader (no python-dotenv needed) ───────────────────────────────────
def _load_dotenv() -> None:
    """Load KEY=value pairs from .env or eval/.env into os.environ."""
    for candidate in [
        os.path.join(os.path.dirname(__file__), ".env"),          # eval/.env
        os.path.join(os.path.dirname(__file__), "..", ".env"),    # project root .env
    ]:
        path = os.path.abspath(candidate)
        if not os.path.isfile(path):
            continue
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                if key and key not in os.environ:
                    os.environ[key] = val
        break   # stop at first found

_load_dotenv()

# ─── colour helpers (graceful fallback when piped) ───────────────────────────
_tty = sys.stdout.isatty()

def c(text, code): return f"\033[{code}m{text}\033[0m" if _tty else text
def bold(t):   return c(t, "1")
def dim(t):    return c(t, "2")
def red(t):    return c(t, "31")
def green(t):  return c(t, "32")
def yellow(t): return c(t, "33")
def cyan(t):   return c(t, "36")
def gray(t):   return c(t, "90")


# ─────────────────────────────────────────────────────────────────────────────
# PII REGEX PATTERNS  (mirrors ZebraRedact/Services/RegexDetector.swift)
# ─────────────────────────────────────────────────────────────────────────────

PATTERNS: dict[str, re.Pattern] = {
    "email":       re.compile(r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b'),
    "phone":       re.compile(r'(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}'),
    "ssn":         re.compile(r'\b\d{3}-\d{2}-\d{4}\b'),
    "credit_card": re.compile(r'\b(?:\d{4}[-\s]?){3}\d{4}\b'),
    "ip_address":  re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
    "api_key":     re.compile(r'\b(?:sk|pk|api)[_\-][A-Za-z0-9_\-]{15,}\b', re.IGNORECASE),
    "bank_routing":re.compile(r'\bRouting:\s*\d{9}\b', re.IGNORECASE),
    "bank_acct":   re.compile(r'\bAcct:\s*\d{8,17}\b', re.IGNORECASE),
    "tax_id":      re.compile(r'\b\d{2}-\d{7}\b'),
    "mrn":         re.compile(r'\bMRN:\s*\d{5,12}\b', re.IGNORECASE),
    "member_id":   re.compile(r'\bMember\s+ID:\s*[A-Z0-9]+\b', re.IGNORECASE),
    "npi":         re.compile(r'\bNPI:\s*\d{10}\b', re.IGNORECASE),
    "dob":         re.compile(r'\bDOB:\s*\d{2}/\d{2}/\d{4}\b', re.IGNORECASE),
    "incident_id": re.compile(r'\bINC-\d{4}-\d{4}\b'),
}

# ─────────────────────────────────────────────────────────────────────────────
# FAKE DATA POOLS  (mirrors ZebraRedact/Services/SemanticReplacer.swift)
# ─────────────────────────────────────────────────────────────────────────────

FAKE: dict[str, list[str]] = {
    "email":       ["contact@example.com", "info@sample.org", "user@placeholder.net"],
    "phone":       ["+1-555-0100", "+1-555-0101", "+1-555-0102"],
    "ssn":         ["000-00-0001", "000-00-0002"],
    "credit_card": ["4000-0000-0000-0001"],
    "ip_address":  ["192.0.2.1", "192.0.2.2", "192.0.2.3"],
    "api_key":     ["sk_example_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"],
    "bank_routing":["Routing: 000000000"],
    "bank_acct":   ["Acct: 0000000000"],
    "tax_id":      ["00-0000001"],
    "mrn":         ["MRN: 00000001"],
    "member_id":   ["Member ID: XXX0000000"],
    "npi":         ["NPI: 0000000000"],
    "dob":         ["DOB: 01/01/1900"],
    "incident_id": ["INC-0000-0000"],
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST DOCUMENTS
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class TestCase:
    name:       str
    category:   str
    text:       str
    known_pii:  list[str]          # items that MUST be absent from redacted output
    description: str = ""

TEST_CASES: list[TestCase] = [

    # ── 1. Business email chain ───────────────────────────────────────────────
    TestCase(
        name="Business Email Chain",
        category="Communication",
        description="Internal email with names, contacts, financials, company names",
        known_pii=[
            "michael.harrison@nexacorp.com", "lisa.chen@nexacorp.com",
            "Jonathan Reed", "Michael Harrison", "Sarah Mitchell",
            "Nexacorp", "Meridian Financial Group", "Petrov Industries",
            "+1 (415) 882-0031", "1-800-555-0192",
        ],
        text="""\
From: michael.harrison@nexacorp.com
To: lisa.chen@nexacorp.com; board@nexacorp.com
Date: March 15, 2024
Subject: Q1 Performance Review – CONFIDENTIAL

Hi Lisa and board members,

Following our call with Jonathan Reed (CFO) yesterday, I wanted to summarize the
key takeaways from the Nexacorp Q1 review.

Revenue came in at $4.7M, down 8% vs Q4 target. The main driver was the loss of
our top enterprise account, Meridian Financial Group, which represented $1.1M ARR.
Jonathan believes we can recover this in Q2 if we close the Petrov Industries deal
by April 30th.

Action items:
- Sarah Mitchell (Sales Lead, ext. 2847) to follow up with Petrov CTO directly
- Legal review of the proposed Petrov contract to be completed by April 5th
- Board call scheduled for April 2nd at 2 PM ET — dial-in: 1-800-555-0192, code 84721#

My cell if anything urgent: +1 (415) 882-0031

Best,
Michael Harrison
VP Operations, Nexacorp
michael.harrison@nexacorp.com | 415-882-0031
"""),

    # ── 2. Shareholder letter ─────────────────────────────────────────────────
    TestCase(
        name="Shareholder Letter",
        category="Finance",
        description="CEO letter with executive names, financials, acquisition details",
        known_pii=[
            "Patricia Okonkwo", "Thomas Brennan", "Ravi Patel",
            "Helios Dynamics", "CloudBridge GmbH",
            "1414 Silicon Ave, Austin TX 78701",
            "patricia.okonkwo@helios.com", "ir@helios.com",
        ],
        text="""\
To Our Shareholders,

Fiscal year 2023 was a defining year for Helios Dynamics. Under the leadership of
CEO Patricia Okonkwo and CFO Thomas Brennan, we achieved record revenue of $892 million,
representing 23% growth year-over-year.

Our flagship product, StellarOS 4.0, captured significant market share in the enterprise
segment. I want to personally thank our CTO, Ravi Patel, whose team shipped 847 features
and maintained 99.97% platform uptime.

In March 2023, we completed the acquisition of CloudBridge GmbH (Munich) for €240 million.
Integration is on track and we expect €45 million in synergies by Q3 2024.

The Board approved a share buyback program of $150 million over 24 months. As of
December 31, 2023, we repurchased 2.3 million shares at an average price of $47.82.

Patricia Okonkwo
Chief Executive Officer
Helios Dynamics, Inc.
NASDAQ: HLDS | 1414 Silicon Ave, Austin TX 78701
patricia.okonkwo@helios.com | ir@helios.com
"""),

    # ── 3. Financial news ─────────────────────────────────────────────────────
    TestCase(
        name="Financial News Article",
        category="News",
        description="Market report with reporter/analyst/exec names and company financials",
        known_pii=[
            "Amanda Kowalski", "Priya Nair", "Marcus Liu", "Daniela Ferreira",
            "Gregory Walsh",
            "Forza Logistics", "Mova", "Sequoia Capital", "Vantage Research Partners",
            "daniela.ferreira@mova.io", "amanda.kowalski@reuters.com",
        ],
        text="""\
MARKETS DESK | Reuters, April 3, 2024

Venture Surge Masks Hidden Stress in Late-Stage Startups

By Amanda Kowalski and Priya Nair

SAN FRANCISCO — Despite a 34% rebound in VC deal volume in Q1 2024, several
late-stage startups are quietly restructuring as runway pressures mount.

Forza Logistics, backed by Sequoia Capital and formerly valued at $2.4 billion,
laid off 140 employees last week — roughly 18% of its workforce — according to
four sources familiar with the matter. CEO Marcus Liu declined to comment.

Meanwhile, payments processor Mova (Series D, $310M raised) missed its Q4 2023
revenue target by 31%, according to internal documents reviewed by Reuters.
Co-founder Daniela Ferreira confirmed the shortfall in a brief email exchange:
"We're refocused on our core SMB segment," she wrote from daniela.ferreira@mova.io.

The Federal Reserve's rate stance remains the key variable, notes Dr. Gregory Walsh,
chief economist at Vantage Research Partners. "Founders extended runway at 2021
valuations that simply don't hold today," Walsh told Reuters on March 28.

© 2024 Reuters. Contact: amanda.kowalski@reuters.com
"""),

    # ── 4. Service contract ───────────────────────────────────────────────────
    TestCase(
        name="Service Agreement",
        category="Legal",
        description="Contract with party details, bank routing/account, tax IDs",
        known_pii=[
            "Gregory Adeyemi", "Claudia Mensah",
            "CrestLine Partners LP", "Orbital Analytics Inc.",
            "88 Wall Street, Suite 1200, New York, NY 10005",
            "3501 Market Street, Philadelphia, PA 19104",
            "47-2918830", "83-4729201",
            "021000021", "8847291034",
            "gregory.adeyemi@crestline.com", "claudia.mensah@orbital.io",
            "(212) 445-8821", "(215) 667-3309",
        ],
        text="""\
SERVICE AGREEMENT

This Agreement is entered into as of January 10, 2024, between:

CLIENT:   CrestLine Partners LP
          Attn: Gregory Adeyemi, Managing Director
          88 Wall Street, Suite 1200, New York, NY 10005
          Tax ID: 47-2918830

PROVIDER: Orbital Analytics Inc.
          Attn: Claudia Mensah, CEO
          3501 Market Street, Philadelphia, PA 19104
          EIN: 83-4729201

SERVICES: Monthly financial modelling and data pipeline services commencing
February 1, 2024, at a monthly retainer of $22,500 USD.

PAYMENT: Wire to Orbital Analytics Inc.
         Routing: 021000021  |  Acct: 8847291034

CONFIDENTIALITY: All data shared, including client positions and trade records,
shall remain strictly confidential.

Signed January 10, 2024:

_______________________          _______________________
Gregory Adeyemi                   Claudia Mensah
Managing Director, CrestLine      CEO, Orbital Analytics
gregory.adeyemi@crestline.com     claudia.mensah@orbital.io
Cell: (212) 445-8821             Cell: (215) 667-3309
"""),

    # ── 5. Medical referral ───────────────────────────────────────────────────
    TestCase(
        name="Medical Referral Note",
        category="Healthcare",
        description="Referral letter with patient demographics, diagnoses, insurance",
        known_pii=[
            "Robert Castillo", "Angela Torres", "Samuel Osei",
            "9420 Wilshire Blvd, Beverly Hills, CA 90210",
            "06/14/1971", "00847219", "BCX4472918K",
            "1234567890",
            "rcastillo71@gmail.com", "(323) 891-4407",
        ],
        text="""\
REFERRAL LETTER — CONFIDENTIAL

Date: February 28, 2024
From: Dr. Angela Torres, MD
      Westside Family Practice
      9420 Wilshire Blvd, Beverly Hills, CA 90210
      Tel: (310) 555-2211 | Fax: (310) 555-2212
      NPI: 1234567890

To:   Dr. Samuel Osei, Cardiologist
      Cedars Medical Heart Center

RE:   Patient: Robert Castillo, DOB: 06/14/1971, MRN: 00847219
      Insurance: BlueCross PPO, Member ID: BCX4472918K

Dear Dr. Osei,

I am referring Mr. Robert Castillo, a 52-year-old male, for cardiology evaluation.
He presented on February 22 with exertional chest pain and a resting BP of 158/94.

His father (deceased) had an MI at age 57. Mr. Castillo is currently on lisinopril
10 mg and atorvastatin 40 mg.

ECG showed non-specific ST changes. Given his risk profile (BMI 31, 20-pack-year
smoking history, HbA1c 6.4%), I am requesting a stress echo and lipid panel.

Mr. Castillo's contact: rcastillo71@gmail.com | (323) 891-4407

Dr. Angela Torres
"""),

    # ── 6. Engineering incident report ────────────────────────────────────────
    TestCase(
        name="Incident Report",
        category="Engineering",
        description="P1 outage report with IPs, API key, on-call engineer, affected companies",
        known_pii=[
            "Ben Nakamura", "Sofia Reyes",
            "devops@company.com", "ben.nakamura@company.com", "sofia.reyes@company.com",
            "+1-669-224-0087",
            "52.23.144.81", "10.0.4.12",
            "sk_prod_4X9mRkL2nQzP8vWjY3eTfH5bsD",
            "TechFlow Inc", "NovaMed Corp",
        ],
        text="""\
INCIDENT REPORT — P1 — Internal Only

Incident ID: INC-2024-0892
Date: March 19, 2024, 03:14 UTC
Reported by: devops@company.com
On-call: Ben Nakamura (ben.nakamura@company.com, +1-669-224-0087)

SUMMARY
Production database cluster (us-east-1, cluster: prod-pg-primary-01) experienced
a full outage for 47 minutes due to failed failover after master node crash.

AFFECTED SYSTEMS
• API Gateway: api.company.com (IP: 52.23.144.81)
• Auth service at auth.company.com — 1.2M requests dropped

TIMELINE
03:14 – Master node prod-db-master-01 (10.0.4.12) stopped responding
03:19 – PagerDuty alert fired, Ben Nakamura paged
03:31 – Root access: ssh ubuntu@10.0.4.12 -i ~/.ssh/prod-key.pem
03:47 – Failover completed; standby promoted
03:51 – Service restored. Postmortem with CTO Sofia Reyes scheduled April 1.

ROOT CAUSE
Misconfigured healthcheck using hardcoded API token:
sk_prod_4X9mRkL2nQzP8vWjY3eTfH5bsD
DO NOT USE — token has been revoked and rotated.

IMPACT
• 8,400 affected users
• Top accounts: TechFlow Inc (enterprise), NovaMed Corp
• Revenue impact estimated: $84,000

OWNER: Ben Nakamura | Reviewed by: Sofia Reyes (sofia.reyes@company.com)
"""),

    # ── 7. Job application cover letter ───────────────────────────────────────
    TestCase(
        name="Cover Letter",
        category="HR",
        description="Job application with personal details, education, work history",
        known_pii=[
            "Isabelle Fontaine", "Nexus Capital Management", "Brightwater University",
            "i.fontaine@gmail.com", "+33 6 12 34 56 78",
            "14 rue de Rivoli, Paris, 75004",
        ],
        text="""\
Isabelle Fontaine
14 rue de Rivoli, Paris, 75004
i.fontaine@gmail.com | +33 6 12 34 56 78

April 10, 2024

Hiring Manager
Global Markets Division

Dear Hiring Manager,

I am writing to apply for the Senior Quantitative Analyst role. I hold an MSc in
Financial Mathematics from Brightwater University (2018) and have spent five years
at Nexus Capital Management, where I led the development of a cross-asset momentum
strategy that generated a Sharpe ratio of 1.87 over a three-year live track record.

My background includes Python, C++, and extensive use of Bloomberg and FactSet APIs.
I have managed a EUR 400M notional derivatives book and am comfortable presenting
risk reports to senior management.

I am relocating to London in July and am available for interviews from May 15th.

Best regards,
Isabelle Fontaine
"""),

    # ── 8. Recorded conversation / transcript ─────────────────────────────────
    TestCase(
        name="Meeting Transcript",
        category="Communication",
        description="Lightly edited sales call transcript with prospects, pricing, contacts",
        known_pii=[
            "Carlos Mendes", "Aisha Oduya", "Ryan Park",
            "Orion Payments", "DataVault Systems",
            "carlos.mendes@orion.com", "(408) 731-9204",
        ],
        text="""\
[Sales Call Transcript — Orion Payments × ZebraRedact Demo]
Date: April 8, 2024  |  Duration: 38 min

RYAN PARK (AE, ZebraRedact):  Thanks for joining, Carlos. So you mentioned you're
evaluating three vendors. What's the main use case driving the evaluation?

CARLOS MENDES (VP Eng, Orion Payments):  We process about 12 million transactions
a day and need to strip PII before logs hit our analytics pipeline. Compliance is
asking for SOC 2 Type II by Q3. My email's carlos.mendes@orion.com if you need
to loop in legal.

RYAN:  Got it. Do you have a data classification layer already, or are you starting
from scratch?

AISHA ODUYA (CISO, Orion Payments):  Partially. We tag credit-card numbers and SSNs
in-flight, but free-text fields — support tickets, chat logs — are a blind spot.
That's really where we're losing sleep.

RYAN:  That's exactly where our NL classifier adds value. What's your current vendor?

CARLOS:  We're trialling DataVault Systems but their false-positive rate on names is
around 40%. My direct line's (408) 731-9204 if you want to set up a POC next week.

RYAN:  Absolutely. I'll send a follow-up to carlos.mendes@orion.com before EOD.
"""),

    # ── 9. Italian news digest (public-figure stress test) ────────────────────
    TestCase(
        name="Italian News Digest",
        category="Journalism",
        description=(
            "Public-affairs newsletter in Italian. No structural PII. "
            "Tests over-redaction of public figures (should stay) and "
            "detection of genuinely private items: unnamed baby's medical "
            "details (identifiable by hospital+age+date+procedure) and "
            "unnamed healthcare workers under criminal investigation."
        ),
        # Most names here are public figures acting in public roles — they
        # should NOT be redacted.  The two genuinely private items are:
        #  1. The baby in Naples: unnamed, but uniquely identifiable from
        #     context (Napoli, cuore, trapianto, 2.5 anni, ~Feb 2025).
        #  2. The six healthcare workers: unnamed but locally identifiable.
        # We list these as known_pii so recall measures whether the tool
        # catches them.  We deliberately exclude public-figure names so the
        # summary also reflects over-redaction (if AI removes Macron etc.).
        known_pii=[
            # The baby — no name, but the cluster uniquely identifies the child
            "bimbo di due anni e mezzo",
            "trapianto di un cuore danneggiato a Napoli",
            # The healthcare workers under investigation
            "sei sanitari indagati",
            "avvisi di garanzia",
        ],
        text="""\
Arte su prescrizione
Non più solo medicine, ma anche arte, musica e spettacoli. Sempre più Paesi stanno introducendo nei loro sistemi sanitari convenzioni con musei e istituzioni culturali per permettere ai medici di prescrivere visite a mostre, teatri o la partecipazione ad attività culturali per trattare disturbi come ansia, stress, lieve depressione o per favorire la riabilitazione (Guardian). L'esempio più recente viene dall'Austria: a partire da novembre 2025 il Vorarlberg Museum ha avviato il progetto pilota "Museo su prescrizione". A disposizione mille biglietti gratuiti che i medici della regione possono richiedere per i propri pazienti (Der Standard).

Lo dice la scienza La semplice visione di opere d'arte come dipinti o sculture può avere effetti positivi misurabili sulla salute fisica e, soprattutto, mentale delle persone, come rivela un recente studio del King's College di Londra. Il primo progetto pilota è partito in Canada nel 2018 (Bbc) e oggi le "prescrizioni di musei" sono sempre più popolari (Art Newspaper). Recentemente anche un report dell'Unione europea ne ha riconosciuto i benefici (Creatives Unite). Il National Health Service, nel Regno Unito, consente da tempo ai professionisti sanitari di effettuare questo tipo di prescrizioni (Guardian).

Avanti il prossimo! In Italia, un passo avanti è stato fatto con la firma del protocollo d'intesa tra ministero della Cultura e ministero della Salute in materia di prescrizione dell'arte come cura che prevede la creazione di un tavolo tecnico che dovrà analizzare l'efficacia di queste misure. Prevista anche l'istituzione, con la Finanziaria 2026, di un Fondo cultura terapeutica e cura sociale con una dotazione di un milione di euro annui (Artribune). Nel nostro Paese ci sono stati già molti esperimenti di arte su prescrizione: ad esempio, nel 2021, con "sciroppo di teatro" i bambini potevano andare a teatro su ricetta del pediatra in ventuno comuni dell'Emilia-Romagna (Vita).

Che settimana!
Trump sta valutando un attacco mirato contro l'Iran nei prossimi giorni per spingere Teheran a concludere un accordo sul dossier nucleare
Si è svolta a Washington la prima riunione del Board of Peace per Gaza: promessi soldi per la ricostruzione e l'invio di soldati da cinque Paesi.
L'Ungheria ha annunciato l'intenzione di bloccare l'approvazione del prestito da 90 miliardi di euro dell'Unione europea destinato all'Ucraina.
Secondo una fonte citata dal Financial Times, Christine Lagarde sarebbe intenzionata a lasciare la presidenza della Bce prima della scadenza del suo mandato.
L'ex principe britannico Andrew Mountbatten-Windsor è stato arrestato, e poi rilasciato, con l'accusa di cattiva condotta in pubblico ufficio nell'ambito dell'indagine sui suoi rapporti con Jeffrey Epstein, il finanziere defunto condannato per reati sessuali su minori.
Il Consiglio dei ministri ha approvato il decreto Bollette e ha stanziato oltre un miliardo di euro per i danni del ciclone Harry.
È morto Jesse Jackson, storico leader dei diritti civili negli Stati Uniti e collaboratore di Martin Luther King.

Furia sui dazi
Trump ha dichiarato che aumenterà al 15% i dazi temporanei sulle importazioni negli Stati Uniti, il livello massimo consentito dalla legge, dopo che la Corte Suprema ha stabilito che il presidente aveva ecceduto i suoi poteri imponendo un prelievo generalizzato del 10%. I nuovi dazi si baserebbero su una legge nota come Sezione 122, che consente dazi fino al 15% per 150 giorni, ma richiede il via libera del Congresso per essere prorogata.

L'economia statunitense ha pagato il prezzo più alto per i dazi imposti da Trump, secondo Fabio Panetta, membro del Consiglio direttivo della Bce.
Il presidente francese Emmanuel Macron si è rallegrato per la decisione della Corte Suprema, mentre il cancelliere tedesco Friedrich Merz ha invocato un "coordinamento europeo" sul tema. La presidente del Consiglio Giorgia Meloni appoggia la linea più blanda della Germania. Intanto Bruxelles sarebbe pronta a colpire gli Usa con controdazi da 93 miliardi.

Diplomazia e guerra
Il Guardian scrive che l'Iran sarebbe disposto a ridurre il grado di purezza della sua scorta di uranio altamente arricchito, sotto la supervisione dell'Agenzia internazionale per l'energia atomica.
Almeno dieci persone sono morte nel Libano orientale in seguito a raid aerei israeliani. L'esercito israeliano ha dichiarato di aver colpito siti appartenenti a Hezbollah.

Mondo reale
Buckingham Palace non si opporrebbe alla decisione del governo britannico di rimuovere Andrew Mountbatten-Windsor dalla linea di successione reale.
Il bimbo di due anni e mezzo che due mesi fa è stato sottoposto al trapianto di un cuore danneggiato a Napoli è morto ieri mattina. I sei sanitari indagati hanno ricevuto i primi avvisi di garanzia: per ora è ipotizzato il reato di lesioni colpose, ma l'accusa potrebbe essere riformulata in omicidio colposo nei prossimi giorni.

Media & Tech
Il regista tedesco-turco Ilker Çatak ha vinto l'Orso d'Oro alla 76ª edizione della Berlinale con "Yellow Letters". Sandra Hüller ha conquistato l'Orso d'Argento per il film "Rose"; Grant Gee ha vinto il premio per la miglior regia con "Everybody Digs Bill Evans".
La Nasa ha posticipato ad aprile la missione Artemis II, la prima con equipaggio umano diretta verso la Luna da oltre mezzo secolo.

Sport
Simone Deromedis e Federico Tomasoni hanno conquistato rispettivamente oro e argento nello skicross maschile. Andrea Giovannini ha vinto il bronzo nella mass start del pattinaggio di velocità. L'Italia ha collezionato in tutto 30 medaglie, di cui 10 ori.
Il tennista spagnolo Carlos Alcaraz, numero uno del mondo, ha sconfitto il francese Arthur Fils 6-2 6-1 conquistando il Qatar Open a Doha.

Weekender
Intervista a Jimmy Wales, il fondatore di Wikipedia: "Con Trump rischiamo il fascismo".
"""),
]


# ─────────────────────────────────────────────────────────────────────────────
# REDACTION IMPLEMENTATIONS
# ─────────────────────────────────────────────────────────────────────────────

def redact_token(text: str) -> tuple[str, dict[str, int]]:
    """Replace structural PII with [TYPE_N] placeholders."""
    result = text
    counts: dict[str, int] = {}
    # Process longest matches first to avoid partial replacements
    matches = []
    for ptype, pattern in PATTERNS.items():
        for m in pattern.finditer(text):
            matches.append((m.start(), m.end(), ptype, m.group()))
    matches.sort(key=lambda x: x[0])

    # Non-overlapping replacement (reverse order to preserve offsets)
    seen_ranges: list[tuple[int, int]] = []
    kept = []
    for start, end, ptype, orig in matches:
        if any(s < end and start < e for s, e in seen_ranges):
            continue
        seen_ranges.append((start, end))
        counts[ptype] = counts.get(ptype, 0) + 1
        kept.append((start, end, ptype, orig, counts[ptype]))

    for start, end, ptype, orig, idx in reversed(kept):
        result = result[:start] + f"[{ptype.upper()}_{idx}]" + result[end:]

    return result, counts


def redact_fake(text: str) -> tuple[str, dict[str, int]]:
    """Replace structural PII with realistic-looking fake values."""
    result = text
    counts: dict[str, int] = {}
    matches = []
    for ptype, pattern in PATTERNS.items():
        for m in pattern.finditer(text):
            matches.append((m.start(), m.end(), ptype, m.group()))
    matches.sort(key=lambda x: x[0])

    seen_ranges: list[tuple[int, int]] = []
    kept = []
    for start, end, ptype, orig in matches:
        if any(s < end and start < e for s, e in seen_ranges):
            continue
        seen_ranges.append((start, end))
        counts[ptype] = counts.get(ptype, 0) + 1
        pool = FAKE.get(ptype, [f"[{ptype.upper()}]"])
        replacement = pool[(counts[ptype] - 1) % len(pool)]
        kept.append((start, end, ptype, orig, replacement))

    for start, end, ptype, orig, rep in reversed(kept):
        result = result[:start] + rep + result[end:]

    return result, counts


def redact_ai(client: anthropic.Anthropic, text: str) -> tuple[str, dict]:
    """
    Use Claude to perform comprehensive, context-aware redaction.
    Returns the redacted text and a summary of what was found.
    """
    resp = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        system="""\
You are a privacy redaction engine. Your task is to redact all personally identifiable
information (PII) and sensitive business data from the input text before it is shared
with an external AI system.

WHAT TO REDACT:
- Personal names (all individuals: authors, subjects, executives, patients, engineers)
- Company / organisation names (customers, partners, competitors, employers)
- Email addresses, phone numbers, physical addresses
- Financial figures tied to a specific entity or deal (revenue, valuation, salary)
- Dates tied to an individual (DOB, appointment dates, deadlines with person context)
- Credentials: API keys, passwords, routing/account numbers, SSNs, MRNs, NPIs
- IP addresses, internal hostnames, infrastructure identifiers
- Project names or internal code-names

REPLACEMENT RULES:
- Use context-aware qualitative replacements where possible, e.g.:
    "Jonathan Reed (CFO)"   →  "the CFO"
    "Meridian Financial"    →  "a key enterprise client"
    "$4.7M revenue"         →  "revenue below target"
    "sk_prod_abc123…"       →  "[REVOKED_API_KEY]"
    "52.23.144.81"          →  "[INTERNAL_IP]"
- Prefer natural language over bracketed tokens so the text stays readable.
- Preserve the document structure, punctuation, and tone exactly.
- Do NOT redact general facts (cities as contexts, job titles without names, industry
  terms, aggregate statistics not tied to a named entity).

Return ONLY the redacted text. No preamble, no explanation, no JSON wrapper.""",
        messages=[{"role": "user", "content": text}],
    )
    redacted = resp.content[0].text
    return redacted, {"input_tokens": resp.usage.input_tokens,
                      "output_tokens": resp.usage.output_tokens}


# ─────────────────────────────────────────────────────────────────────────────
# EVALUATION
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class ModeResult:
    mode:           str
    redacted_text:  str
    found_count:    int          # structural patterns detected
    recall:         float        # fraction of known_pii absent from redacted text
    leaked_items:   list[str]    # per Claude's audit
    risk_level:     str          # none | low | medium | high
    semantic_note:  str
    latency_ms:     int
    audit_tokens:   int = 0


@dataclass
class CaseResult:
    case:       TestCase
    modes:      dict[str, ModeResult] = field(default_factory=dict)


def compute_recall(known_pii: list[str], redacted_text: str) -> tuple[float, list[str]]:
    """Check how many known PII strings are still present verbatim in the redacted text."""
    still_present = [item for item in known_pii
                     if item.lower() in redacted_text.lower()]
    recall = 1.0 - len(still_present) / max(1, len(known_pii))
    return recall, still_present


def audit_leakage(
    client: anthropic.Anthropic,
    original: str,
    redacted: str,
    known_pii: list[str],
) -> tuple[list[str], str, str, int]:
    """
    Ask Claude to act as a privacy auditor and identify what can still be inferred
    from the redacted text.
    Returns (leaked_items, risk_level, semantic_note, tokens_used).
    """
    pii_summary = "\n".join(f"  - {item}" for item in known_pii)
    prompt = f"""\
You are a privacy auditor evaluating a redacted document.

The original document contained the following sensitive items that should be hidden:
{pii_summary}

Below is the redacted version. Your job:
1. Identify any sensitive items that remain INFERABLE — even indirectly — from the
   redacted text (e.g. a company identifiable from unique metrics, a person from
   their role + organisation combination, an address from a unique landmark).
2. Assess the overall residual risk.
3. Note whether the redacted text still makes sense for its intended purpose.

Redacted text:
\"\"\"
{redacted}
\"\"\"

Respond with a JSON object ONLY — no markdown, no explanation outside the JSON:
{{
  "leaked_items": ["<concise description of each inferable item>"],
  "risk_level": "none|low|medium|high",
  "semantic_quality": "<one sentence on usefulness of the redacted text>"
}}"""

    resp = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = resp.content[0].text.strip()
    tokens = resp.usage.input_tokens + resp.usage.output_tokens
    try:
        # Strip any accidental markdown fences
        raw = re.sub(r'^```(?:json)?\s*', '', raw)
        raw = re.sub(r'\s*```$', '', raw)
        data = json.loads(raw)
        return (
            data.get("leaked_items", []),
            data.get("risk_level", "unknown"),
            data.get("semantic_quality", ""),
            tokens,
        )
    except json.JSONDecodeError:
        return (["(audit parse error)"], "unknown", "", tokens)


# ─────────────────────────────────────────────────────────────────────────────
# RUNNER
# ─────────────────────────────────────────────────────────────────────────────

def run_case(
    client: anthropic.Anthropic,
    case: TestCase,
    modes: list[str],
) -> CaseResult:
    result = CaseResult(case=case)

    for mode in modes:
        t0 = time.monotonic()

        if mode == "token":
            redacted, counts = redact_token(case.text)
            found = sum(counts.values())
        elif mode == "fake":
            redacted, counts = redact_fake(case.text)
            found = sum(counts.values())
        elif mode == "ai":
            redacted, meta = redact_ai(client, case.text)
            found = -1   # AI doesn't surface a count
        else:
            continue

        latency = int((time.monotonic() - t0) * 1000)

        recall, still_present = compute_recall(case.known_pii, redacted)

        leaked, risk, semantic, audit_tok = audit_leakage(
            client, case.text, redacted, case.known_pii
        )

        result.modes[mode] = ModeResult(
            mode=mode,
            redacted_text=redacted,
            found_count=found,
            recall=recall,
            leaked_items=leaked,
            risk_level=risk,
            semantic_note=semantic,
            latency_ms=latency,
            audit_tokens=audit_tok,
        )

    return result


# ─────────────────────────────────────────────────────────────────────────────
# REPORTING
# ─────────────────────────────────────────────────────────────────────────────

RISK_COLOUR = {
    "none":    green,
    "low":     yellow,
    "medium":  yellow,
    "high":    red,
    "unknown": dim,
}

def risk_badge(level: str) -> str:
    col = RISK_COLOUR.get(level, dim)
    icons = {"none": "✓", "low": "▲", "medium": "⚠", "high": "✗", "unknown": "?"}
    return col(f"{icons.get(level, '?')} {level.upper()}")


def recall_bar(recall: float, width: int = 20) -> str:
    filled = round(recall * width)
    bar = "█" * filled + "░" * (width - filled)
    pct = f"{recall * 100:.0f}%"
    col = green if recall >= 0.8 else (yellow if recall >= 0.5 else red)
    return col(bar) + f" {pct}"


def print_report(results: list[CaseResult]) -> None:
    w = 72
    print()
    print(bold("━" * w))
    print(bold(f"  ZebraRedact Accuracy Evaluation  │  {len(results)} documents"))
    print(bold("━" * w))

    totals: dict[str, dict] = {"token": {"recall": [], "risk": []},
                                "fake":  {"recall": [], "risk": []},
                                "ai":    {"recall": [], "risk": []}}

    for cr in results:
        print()
        print(cyan(f"  📄 {cr.case.name}") + dim(f"  [{cr.case.category}]"))
        print(dim(f"     {cr.case.description}"))
        print(dim(f"     {len(cr.case.known_pii)} known PII items to hide"))
        print()

        for mode, mr in cr.modes.items():
            label = {"token": "TOKEN   ", "fake": "FAKE    ", "ai": "AI      "}[mode]
            print(f"    {bold(label)}")

            # Recall bar
            print(f"      Recall       {recall_bar(mr.recall)}")

            # Leakage
            if mr.leaked_items:
                print(f"      Leakage      {risk_badge(mr.risk_level)}")
                for item in mr.leaked_items[:4]:   # cap at 4 to avoid wall of text
                    print(f"               → {dim(textwrap.shorten(item, 60))}")
                if len(mr.leaked_items) > 4:
                    print(f"               → {dim(f'…+{len(mr.leaked_items)-4} more')}")
            else:
                print(f"      Leakage      {risk_badge(mr.risk_level)}  (none identified)")

            # Semantic quality
            if mr.semantic_note:
                wrapped = textwrap.fill(mr.semantic_note, 55,
                                        subsequent_indent=" " * 19)
                print(f"      Usability    {dim(wrapped)}")

            print(f"      Latency      {dim(str(mr.latency_ms) + ' ms')}")
            print()

            # Accumulate for summary
            if mode in totals:
                totals[mode]["recall"].append(mr.recall)
                totals[mode]["risk"].append(mr.risk_level)

        print(dim("  " + "─" * (w - 2)))

    # Summary table
    print()
    print(bold("  SUMMARY"))
    print(f"  {'Mode':<10} {'Avg Recall':<16} {'High-Risk Cases':<18} {'Safe Cases'}")
    print(dim("  " + "─" * 60))
    for mode in ["token", "fake", "ai"]:
        if not totals[mode]["recall"]:
            continue
        avg_recall = sum(totals[mode]["recall"]) / len(totals[mode]["recall"])
        high_risk  = sum(1 for r in totals[mode]["risk"] if r in ("high", "medium"))
        safe       = sum(1 for r in totals[mode]["risk"] if r == "none")
        col = green if avg_recall >= 0.8 else (yellow if avg_recall >= 0.5 else red)
        print(f"  {mode.upper():<10} {col(f'{avg_recall*100:.1f}%'):<25} "
              f"{str(high_risk):<18} {str(safe)}")
    print()


def save_json(results: list[CaseResult], path: str) -> None:
    out = []
    for cr in results:
        modes_data = {}
        for mode, mr in cr.modes.items():
            modes_data[mode] = {
                "recall": round(mr.recall, 3),
                "risk_level": mr.risk_level,
                "leaked_items": mr.leaked_items,
                "semantic_note": mr.semantic_note,
                "redacted_text": mr.redacted_text,
                "latency_ms": mr.latency_ms,
            }
        out.append({
            "case": cr.case.name,
            "category": cr.case.category,
            "known_pii_count": len(cr.case.known_pii),
            "modes": modes_data,
        })
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
    print(dim(f"  JSON saved → {path}"))


# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="ZebraRedact accuracy evaluation")
    parser.add_argument("--mode", choices=["token", "fake", "ai"],
                        help="Run only this mode (default: all three)")
    parser.add_argument("--case", metavar="NAME",
                        help="Run only cases whose name contains NAME (case-insensitive)")
    parser.add_argument("--json", action="store_true",
                        help="Save machine-readable results to eval/reports/latest.json")
    parser.add_argument("--show-redacted", action="store_true",
                        help="Print the full redacted text for each case/mode")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print(red("Error: ANTHROPIC_API_KEY environment variable not set."))
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    modes = [args.mode] if args.mode else ["token", "fake", "ai"]
    cases = TEST_CASES
    if args.case:
        cases = [c for c in TEST_CASES if args.case.lower() in c.name.lower()]
        if not cases:
            print(red(f"No cases matching '{args.case}'. Available:"))
            for c in TEST_CASES:
                print(f"  {c.name}")
            sys.exit(1)

    print(bold(f"\n  Running {len(modes)} mode(s) × {len(cases)} case(s) …"))
    print(dim("  This calls the Anthropic API — each case takes 3–15 s.\n"))

    results: list[CaseResult] = []
    for i, case in enumerate(cases, 1):
        print(dim(f"  [{i}/{len(cases)}] {case.name} …"), end="", flush=True)
        cr = run_case(client, case, modes)
        results.append(cr)
        print(dim(" done"))

        if args.show_redacted:
            for mode, mr in cr.modes.items():
                print(f"\n{'─'*60}")
                print(bold(f"  {case.name} — {mode.upper()}"))
                print("─"*60)
                print(textwrap.indent(mr.redacted_text, "  "))

    print_report(results)

    if args.json:
        os.makedirs("eval/reports", exist_ok=True)
        ts = time.strftime("%Y%m%d_%H%M%S")
        path = f"eval/reports/{ts}.json"
        save_json(results, path)


if __name__ == "__main__":
    main()
