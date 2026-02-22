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
# SUITE 1 — COREFERENCE CONSISTENCY
# Same entity, multiple surface forms.  All should be treated uniformly.
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class ConsistencyCase:
    name:          str
    description:   str
    text:          str
    # list of (canonical_name, [surface_form, …])
    entity_groups: list[tuple[str, list[str]]]

CONSISTENCY_CASES: list[ConsistencyCase] = [
    ConsistencyCase(
        name="Multi-Form Person Reference",
        description="Same CFO mentioned as full name, first name, surname, initial, and role",
        entity_groups=[("Jonathan Reed", ["Jonathan Reed", "Jonathan", "Reed", "J. Reed"])],
        text="""\
Jonathan Reed (CFO) opened the budget review at 9 AM.
Jonathan confirmed the Q3 figures were accurate.
Reed signed the capital-expenditure approval at 15:07.
The CFO later denied any prior knowledge of the pricing discrepancy.
HR records show J. Reed joined from Goldman in 2019.
An anonymous source close to him suggested the board was misled.
""",
    ),
    ConsistencyCase(
        name="Company Alias Chain",
        description="Same company referred to by full name, acronym, shortened form, and 'the company'",
        entity_groups=[("Meridian Financial Group",
                        ["Meridian Financial Group", "MFG", "Meridian"])],
        text="""\
Meridian Financial Group reported record pre-tax profits of $340M last quarter.
MFG's trading desk outperformed all peer firms by a wide margin.
The company issued a brief press release on Friday afternoon.
Meridian confirmed the acquisition of CrossBay Capital via its IR team.
Insiders say the firm plans to rebrand within 18 months.
""",
    ),
    ConsistencyCase(
        name="Patient Coreference Chain",
        description="Patient named once then referred to by pronouns and role — all should be hidden",
        entity_groups=[("Robert Castillo", ["Robert Castillo", "Mr. Castillo", "Robert"])],
        text="""\
Robert Castillo was admitted on February 22 with chest pain.
Mr. Castillo's ECG showed non-specific ST changes.
Robert denied any prior cardiac history during intake.
He is currently on lisinopril 10 mg and atorvastatin 40 mg.
The patient's wife confirmed he had not taken his morning dose.
""",
    ),
]


# ─────────────────────────────────────────────────────────────────────────────
# SUITE 2 — ADVERSARIAL EVASION
# PII deliberately formatted to defeat pattern matching.
# ─────────────────────────────────────────────────────────────────────────────

ADVERSARIAL_CASES: list[TestCase] = [
    TestCase(
        name="Obfuscated Contacts",
        category="Adversarial",
        description="Email (bracket notation), phone (extra spaces), SSN (spaces not dashes)",
        known_pii=["j.harrison@nexacorp.com", "415 882 0031", "472-18-3901"],
        text="""\
Reach me at j.harrison AT nexacorp DOT com for the contract draft.
Call 415 882 00 31 if urgent — I'm on Pacific time.
SSN on file: 472 18 3901 (spaces, not dashes — old HR format).
Backup line: (415).882.0031.
""",
    ),
    TestCase(
        name="Split and Encoded Credentials",
        category="Adversarial",
        description="API key split across lines, IP in hex/decimal mix, token in URL fragment",
        known_pii=["sk_prod_ABC123XYZ789mno456", "10.0.4.12", "ghp_TokenABCDEF1234567890xy"],
        text="""\
Production key (parts concatenated at runtime):
  part1 = "sk_prod_"
  part2 = "ABC123XYZ789mno456"

DB server at 0x0A00040C  (= 10.0.4.12 in hex).
Auth header expected: Bearer ghp_TokenABCDEF1234567890xy
Docs at https://internal.company.com/wiki#token=ghp_TokenABCDEF1234567890xy
""",
    ),
    TestCase(
        name="Implicit Identity (No Name)",
        category="Adversarial",
        description="No name present — identity fully recoverable from role + org + location + year",
        known_pii=["identity of the individual described"],
        text="""\
The only female named partner at the firm's Austin office, who transferred
from the New York litigation group in 2021 after clerking for the Ninth Circuit,
and who leads the fintech regulatory practice, approved the client filing.
Her compensation exceeded $2.1M last year according to the partnership agreement.
""",
    ),
    TestCase(
        name="PII in Structured Data",
        category="Adversarial",
        description="PII embedded in JSON keys, SQL, and log lines — not natural language",
        known_pii=["alice@corp.com", "192.168.1.105", "4111-1111-1111-1111"],
        text="""\
SELECT * FROM users WHERE email = 'alice@corp.com' AND active = 1;

{"user": {"email": "alice@corp.com", "ip": "192.168.1.105", "card_last4": "1111"}}

2024-03-19T03:14:22Z INFO  payment charged card=4111-1111-1111-1111 user=alice@corp.com
""",
    ),
]


# ─────────────────────────────────────────────────────────────────────────────
# SUITE 3 — DOMAIN BLIND SPOTS
# Document types the base test corpus doesn't cover.
# ─────────────────────────────────────────────────────────────────────────────

DOMAIN_CASES: list[TestCase] = [
    TestCase(
        name="Legal Filing",
        category="Legal",
        description="Federal complaint with case number, bar ID, party names, and counsel email",
        known_pii=[
            "Elena Vasquez", "TerraForm Holdings LLC",
            "Case No. 24-CV-08812", "Bar No. CA-291847",
            "elena.vasquez@counsel.com",
        ],
        text="""\
IN THE UNITED STATES DISTRICT COURT
NORTHERN DISTRICT OF CALIFORNIA

Case No. 24-CV-08812

PLAINTIFF: Elena Vasquez
v.
DEFENDANT: TerraForm Holdings LLC

Counsel for Plaintiff: David Osei, Esq.
Bar No. CA-291847 | elena.vasquez@counsel.com

COMPLAINT FOR BREACH OF FIDUCIARY DUTY

Plaintiff Elena Vasquez alleges that TerraForm Holdings LLC, through its
managing partners, misappropriated $2.1M in restricted stock grants between
January and September 2023. Plaintiff demands compensatory damages, disgorgement,
and injunctive relief.

JURY TRIAL DEMANDED.
""",
    ),
    TestCase(
        name="HR Compensation Record",
        category="HR",
        description="Salary adjustment memo with employee ID, level, manager chain, and equity",
        known_pii=[
            "Priya Mehta", "EMP-00419",
            "priya.mehta@techcorp.com", "$198,000", "$214,000",
        ],
        text="""\
COMPENSATION ADJUSTMENT — CONFIDENTIAL

Employee:   Priya Mehta (EMP-00419)
Level:      L6 Senior Engineer
Manager:    Carlos Webb (L7, EMP-00271)
Department: Platform Infrastructure

Current Base:   $198,000
Proposed Base:  $214,000  (+8.1%)
Equity Refresh: 800 RSUs vesting over 4 years
Bonus Target:   20% of base

Effective: April 1, 2024
Approved by: VP People Operations

HR contact: priya.mehta@techcorp.com for acknowledgement signature.
""",
    ),
    TestCase(
        name="Source Code with Hardcoded Secrets",
        category="Engineering",
        description="Production config with DB connection string, API keys, and internal hostnames",
        known_pii=[
            "postgres://admin:S3cr3tPass@db.internal.company.com:5432/prod",
            "sk_live_51HxxxxxxxxxxxxxxxxxxxxABCDEF",
            "whsec_abc123def456ghi789",
            "db.internal.company.com",
        ],
        text="""\
# config/production.yml  — DO NOT COMMIT

database:
  url: postgres://admin:S3cr3tPass@db.internal.company.com:5432/prod
  pool_size: 20

cache:
  url: redis://cache.internal:6379
  ttl: 3600

stripe:
  secret_key: sk_live_51HxxxxxxxxxxxxxxxxxxxxABCDEF
  webhook_secret: whsec_abc123def456ghi789

sentry:
  dsn: https://abc123@o12345.ingest.sentry.io/67890

feature_flags:
  new_checkout: true
  beta_users: [user_1234, user_5678]
""",
    ),
    TestCase(
        name="Financial Due Diligence Memo",
        category="Finance",
        description="M&A memo with CUSIP, fund name, target company, and deal economics",
        known_pii=[
            "NovaBridge Capital Partners III",
            "Arcturus Semiconductor GmbH",
            "CUSIP 64110L106",
            "Hans-Peter Kohl",
            "€180M", "7.2x EBITDA",
        ],
        text="""\
CONFIDENTIAL — INVESTMENT COMMITTEE MEMO

Fund:    NovaBridge Capital Partners III
Target:  Arcturus Semiconductor GmbH (Munich)
CUSIP:   64110L106 (parent listed entity)
Contact: Hans-Peter Kohl, CEO (h.kohl@arcturus.de)

DEAL ECONOMICS
Proposed enterprise value:  €180M  (7.2x trailing EBITDA)
Equity check:               €95M
Debt financing:             €85M (term loan, L+375bps)
Expected IRR:               24–28% (base case)

DILIGENCE STATUS
Financial:  Complete (PwC signed off March 14)
Legal:      In progress — environmental liabilities flagged
Technology: Pending — source code audit scheduled April 2

IC vote required by April 10, 2024.
""",
    ),
]


# ─────────────────────────────────────────────────────────────────────────────
# SUITE 4 — CROSS-REFERENCE PAIRS
# Two documents, each safe alone — together they re-identify.
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class CrossRefPair:
    name:         str
    description:  str
    doc_a:        str
    doc_b:        str
    target:       str   # what gets exposed when both are combined
    known_pii_a:  list[str]
    known_pii_b:  list[str]

CROSSREF_PAIRS: list[CrossRefPair] = [
    CrossRefPair(
        name="Offer Letter + Org Chart",
        description=(
            "Doc A: offer letter (no name, but exact comp). "
            "Doc B: org chart update (name + role). "
            "Combined: full compensation profile of a named individual."
        ),
        doc_a="""\
OFFER LETTER

Congratulations! We are pleased to extend an offer for the role of VP of Engineering
at our Series B startup in San Francisco.

Compensation package:
  Base salary:    $310,000
  Equity:         0.8% (4-year vest, 1-year cliff)
  Signing bonus:  $25,000

Start date: June 3, 2024.  Reports to: CEO.
""",
        doc_b="""\
ORG CHART UPDATE — Q2 2024

Marcus Webb joins as VP of Engineering, reporting to CEO Priya Kapoor.
Prior role: Head of Platform at DataStream Inc.
Location: San Francisco office.
Slack: @marcus.webb | marcus.webb@company.com
""",
        target="Marcus Webb's exact compensation and equity package",
        known_pii_a=["$310,000", "0.8%", "$25,000"],
        known_pii_b=["Marcus Webb", "Priya Kapoor", "DataStream Inc.", "marcus.webb@company.com"],
    ),
    CrossRefPair(
        name="Clinical Note + Appointment Schedule",
        description=(
            "Doc A: clinical note with MRN only (no patient name, but sensitive diagnosis). "
            "Doc B: appointment schedule linking MRN to full name. "
            "Combined: HIPAA-level breach — name + psychiatric diagnosis."
        ),
        doc_a="""\
CLINICAL NOTE — MRN 00847219
Date: February 22, 2024

Chief complaint: Recurrent depressive episodes, third inpatient admission this year.
PHQ-9 score: 19 (severe). Current meds: sertraline 100mg, bupropion 150mg.
Discussed ECT as escalation option. Patient consented to 6-week trial.
Discharge target: March 1 pending response to medication adjustment.
""",
        doc_b="""\
APPOINTMENT SCHEDULE — MARCH 2024

09:00 — Robert Castillo (MRN 00847219) — Dr. Osei follow-up
11:30 — Maria Santos (MRN 00291047) — intake assessment
14:00 — David Park (MRN 00391822) — medication review
""",
        target="Robert Castillo's psychiatric diagnosis, ECT consent, and admission history",
        known_pii_a=["MRN 00847219"],
        known_pii_b=["Robert Castillo", "MRN 00847219"],
    ),
    CrossRefPair(
        name="Whistleblower Complaint + Directory",
        description=(
            "Doc A: anonymous complaint describing the whistleblower's role and department. "
            "Doc B: department directory. "
            "Combined: anonymous source is fully identifiable."
        ),
        doc_a="""\
ANONYMOUS COMPLAINT — submitted via ethics hotline

I am the only woman on the 4-person derivatives structuring team in the London office.
I have been excluded from client calls since raising concerns about model risk
in Q3 2023. My direct manager has since given me a below-target review.
I am filing this complaint under the firm's whistleblower policy.
""",
        doc_b="""\
DERIVATIVES STRUCTURING — LONDON TEAM DIRECTORY

  James Thornton    — VP, Rates Structuring
  Aiko Nakamura     — Associate, Credit Derivatives
  Sophie Laurent    — Analyst, Equity Structuring
  Kevin O'Brien     — Analyst, FX Derivatives

Manager: Richard Hale (Managing Director)
""",
        target="Sophie Laurent as the whistleblower",
        known_pii_a=["identity of the complainant"],
        known_pii_b=["Sophie Laurent", "Aiko Nakamura", "James Thornton"],
    ),
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


@dataclass
class ConsistencyResult:
    case:        ConsistencyCase
    mode:        str
    form_audit:  dict[str, bool]   # surface_form: True if removed
    assessment:  str               # Claude's implicit-reference verdict
    tokens:      int


@dataclass
class CrossRefResult:
    pair:          CrossRefPair
    mode:          str
    reidentified:  bool
    what_revealed: str
    tokens:        int


@dataclass
class ExtendedResults:
    consistency:  list[ConsistencyResult]      = field(default_factory=list)
    adversarial:  list[CaseResult]             = field(default_factory=list)
    # {case_name: {mode: (could_identify, identified_as)}}
    reid_map:     dict                         = field(default_factory=dict)
    domain:       list[CaseResult]             = field(default_factory=list)
    crossref:     list[CrossRefResult]         = field(default_factory=list)
    longitudinal: dict[str, tuple]             = field(default_factory=dict)
    corrections:  dict                         = field(default_factory=dict)


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
# EXTENDED EVALUATIONS (suites 1–6)
# ─────────────────────────────────────────────────────────────────────────────

def _parse_json_response(raw: str) -> dict:
    raw = raw.strip()
    raw = re.sub(r'^```(?:json)?\s*', '', raw)
    raw = re.sub(r'\s*```$', '', raw)
    return json.loads(raw)


# Suite 2 — Re-identification attack ─────────────────────────────────────────

def test_reidentification(
    client: anthropic.Anthropic,
    redacted: str,
    target_hint: str = "",
) -> tuple[bool, str, int]:
    """
    Adversary test: given only the redacted text, can you name the subject?
    Returns (could_identify, what_was_identified, tokens).
    """
    hint_line = f"Hint about what to look for: {target_hint}\n\n" if target_hint else ""
    prompt = f"""\
You are an adversary. Using ONLY the redacted text below — no external knowledge —
try to identify specific real people, companies, events, or sensitive facts.
{hint_line}Redacted text:
\"\"\"
{redacted}
\"\"\"

Respond with JSON only:
{{
  "could_identify": true|false,
  "identified_as": "<what you could identify, or null>",
  "confidence": "high|medium|low",
  "reasoning": "<how you reached this conclusion>"
}}"""
    resp = client.messages.create(
        model="claude-haiku-4-5-20251001", max_tokens=512,
        messages=[{"role": "user", "content": prompt}],
    )
    tokens = resp.usage.input_tokens + resp.usage.output_tokens
    try:
        data = _parse_json_response(resp.content[0].text)
        return data.get("could_identify", False), data.get("identified_as") or "", tokens
    except (json.JSONDecodeError, KeyError):
        return False, "(parse error)", tokens


# Suite 1 — Coreference consistency ──────────────────────────────────────────

def test_consistency(
    client: anthropic.Anthropic,
    case: ConsistencyCase,
    redacted: str,
) -> tuple[dict[str, bool], str, int]:
    """
    Check whether every surface form of each entity was removed.
    Also asks Claude whether implicit references (pronouns, role-only) remain.
    Returns ({form: was_removed}, claude_assessment, tokens).
    """
    form_results: dict[str, bool] = {}
    for _, forms in case.entity_groups:
        for form in forms:
            form_results[form] = form.lower() not in redacted.lower()

    lines = "\n".join(
        f"  {'✓' if removed else '✗'} '{form}' — {'removed' if removed else 'STILL PRESENT'}"
        for form, removed in form_results.items()
    )
    prompt = f"""\
A document was redacted. The same entity appears under multiple surface forms.

Verbatim-form audit:
{lines}

Redacted text:
\"\"\"
{redacted}
\"\"\"

Are there remaining IMPLICIT references (pronouns like "he/she/they", role-only
phrases like "the CFO", or possessives like "his decision") that still point to
the same entity and allow re-identification?

Respond with JSON only:
{{
  "consistent": true|false,
  "residual_references": ["<each remaining implicit reference>"],
  "assessment": "<one sentence>"
}}"""
    resp = client.messages.create(
        model="claude-haiku-4-5-20251001", max_tokens=512,
        messages=[{"role": "user", "content": prompt}],
    )
    tokens = resp.usage.input_tokens + resp.usage.output_tokens
    try:
        data = _parse_json_response(resp.content[0].text)
        return form_results, data.get("assessment", ""), tokens
    except (json.JSONDecodeError, KeyError):
        return form_results, "(parse error)", tokens


# Suite 3 — Cross-reference attack ────────────────────────────────────────────

def test_cross_reference(
    client: anthropic.Anthropic,
    pair: CrossRefPair,
    redacted_a: str,
    redacted_b: str,
) -> tuple[bool, str, int]:
    """
    Combine two independently-redacted documents and check whether together
    they re-expose the target information.
    Returns (reidentified, what_was_revealed, tokens).
    """
    combined = f"--- Document 1 ---\n{redacted_a}\n\n--- Document 2 ---\n{redacted_b}"
    prompt = f"""\
Two documents were redacted independently. Read them TOGETHER and determine
whether the combination reveals: {pair.target}

Combined documents:
\"\"\"
{combined}
\"\"\"

Respond with JSON only:
{{
  "reidentified": true|false,
  "what_was_revealed": "<specific information recovered, or null>",
  "mechanism": "<how the two documents together leaked this, or null>"
}}"""
    resp = client.messages.create(
        model="claude-haiku-4-5-20251001", max_tokens=512,
        messages=[{"role": "user", "content": prompt}],
    )
    tokens = resp.usage.input_tokens + resp.usage.output_tokens
    try:
        data = _parse_json_response(resp.content[0].text)
        return data.get("reidentified", False), data.get("what_was_revealed") or "", tokens
    except (json.JSONDecodeError, KeyError):
        return False, "(parse error)", tokens


# Suite 5 — Task utility ──────────────────────────────────────────────────────

def test_task_utility(
    client: anthropic.Anthropic,
    original: str,
    redacted: str,
    task: str,
) -> tuple[float, str, int]:
    """
    Ask Claude to complete `task` on both original and redacted text, then score
    how much utility the redacted version preserves (0.0 = useless, 1.0 = identical).
    """
    def ask(text: str) -> tuple[str, int]:
        r = client.messages.create(
            model="claude-haiku-4-5-20251001", max_tokens=300,
            messages=[{"role": "user", "content": f"{task}\n\nText:\n{text}"}],
        )
        return r.content[0].text.strip(), r.usage.input_tokens + r.usage.output_tokens

    ans_orig, tok1 = ask(original)
    ans_red,  tok2 = ask(redacted)

    judge = client.messages.create(
        model="claude-haiku-4-5-20251001", max_tokens=256,
        messages=[{"role": "user", "content": f"""\
Task: {task}

Answer from ORIGINAL (unredacted) text:
{ans_orig}

Answer from REDACTED text:
{ans_red}

Score how well the redacted answer serves the same purpose as the original.
1.0 = identical utility, 0.0 = completely unusable.

Respond with JSON only: {{"score": 0.0, "explanation": "..."}}
"""}],
    )
    tok3 = judge.usage.input_tokens + judge.usage.output_tokens
    try:
        data = _parse_json_response(judge.content[0].text)
        return float(data.get("score", 0.5)), data.get("explanation", ""), tok1 + tok2 + tok3
    except (json.JSONDecodeError, ValueError, KeyError):
        return 0.5, "(parse error)", tok1 + tok2 + tok3


# Suite 6 — Longitudinal stability ────────────────────────────────────────────

def test_longitudinal(redact_fn, text: str, runs: int = 3) -> tuple[bool, str]:
    """
    Run the same redaction function N times and verify token assignments are stable.
    Returns (is_stable, diff_description).
    """
    outputs = [redact_fn(text)[0] for _ in range(runs)]
    if all(o == outputs[0] for o in outputs):
        return True, f"All {runs} runs produced identical output."
    for i in range(1, runs):
        if outputs[i] != outputs[0]:
            lines_a = outputs[0].splitlines()
            lines_b = outputs[i].splitlines()
            diffs = [(n + 1, a, b)
                     for n, (a, b) in enumerate(zip(lines_a, lines_b)) if a != b]
            if diffs:
                ln, a, b = diffs[0]
                return False, f"Run {i+1} differs at line {ln}: «{a[:50]}» vs «{b[:50]}»"
    return False, "Outputs differ in length between runs."


# Suite 4 — User correction logger ────────────────────────────────────────────

CORRECTIONS_PATH = os.path.join(os.path.dirname(__file__), "corrections.jsonl")

def log_correction(
    correction_type: str,   # "false_positive" | "false_negative"
    original_text:   str,
    corrected_to:    str,
    context:         str = "",
    path:            str = CORRECTIONS_PATH,
) -> None:
    """
    Append a labelled correction to corrections.jsonl for future analysis.
    false_positive = tool over-redacted (user hit Restore Original).
    false_negative = tool missed it (user manually tagged it).
    """
    entry = {
        "ts":              time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "correction_type": correction_type,
        "original_text":   original_text,
        "corrected_to":    corrected_to,
        "context":         context[:300],
    }
    with open(path, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def summarise_corrections(path: str = CORRECTIONS_PATH) -> dict:
    """Read corrections.jsonl and return summary statistics."""
    if not os.path.isfile(path):
        return {"total": 0, "false_positive": 0, "false_negative": 0, "examples": []}
    entries = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    fp = sum(1 for e in entries if e.get("correction_type") == "false_positive")
    fn = sum(1 for e in entries if e.get("correction_type") == "false_negative")
    return {
        "total": len(entries),
        "false_positive": fp,
        "false_negative": fn,
        "examples": entries[-5:],   # last 5 corrections
    }


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
# EXTENDED RUNNER
# ─────────────────────────────────────────────────────────────────────────────

def _do_redact(client: anthropic.Anthropic, mode: str, text: str) -> str:
    """Dispatch to the right redaction function and return just the redacted text."""
    if mode == "token":
        return redact_token(text)[0]
    elif mode == "fake":
        return redact_fake(text)[0]
    else:
        return redact_ai(client, text)[0]


def run_extended(
    client: anthropic.Anthropic,
    suites: list[str],
    modes: list[str],
) -> ExtendedResults:
    ext = ExtendedResults()

    if "consistency" in suites:
        print(dim("\n  [Suite: Consistency]"))
        for cc in CONSISTENCY_CASES:
            print(dim(f"    {cc.name} …"), end="", flush=True)
            for mode in modes:
                redacted = _do_redact(client, mode, cc.text)
                form_audit, assessment, tokens = test_consistency(client, cc, redacted)
                ext.consistency.append(ConsistencyResult(
                    case=cc, mode=mode,
                    form_audit=form_audit, assessment=assessment, tokens=tokens,
                ))
            print(dim(" done"))

    if "adversarial" in suites:
        print(dim("\n  [Suite: Adversarial]"))
        for case in ADVERSARIAL_CASES:
            print(dim(f"    {case.name} …"), end="", flush=True)
            cr = run_case(client, case, modes)
            ext.adversarial.append(cr)
            ext.reid_map[case.name] = {}
            for mode, mr in cr.modes.items():
                could_id, identified_as, _ = test_reidentification(client, mr.redacted_text)
                ext.reid_map[case.name][mode] = (could_id, identified_as)
            print(dim(" done"))

    if "domain" in suites:
        print(dim("\n  [Suite: Domain]"))
        for case in DOMAIN_CASES:
            print(dim(f"    {case.name} …"), end="", flush=True)
            cr = run_case(client, case, modes)
            ext.domain.append(cr)
            print(dim(" done"))

    if "crossref" in suites:
        print(dim("\n  [Suite: Cross-Reference]"))
        for pair in CROSSREF_PAIRS:
            print(dim(f"    {pair.name} …"), end="", flush=True)
            for mode in modes:
                redacted_a = _do_redact(client, mode, pair.doc_a)
                redacted_b = _do_redact(client, mode, pair.doc_b)
                reidentified, what, tokens = test_cross_reference(
                    client, pair, redacted_a, redacted_b
                )
                ext.crossref.append(CrossRefResult(
                    pair=pair, mode=mode,
                    reidentified=reidentified, what_revealed=what, tokens=tokens,
                ))
            print(dim(" done"))

    if "longitudinal" in suites:
        print(dim("\n  [Suite: Longitudinal]"))
        sample_text = TEST_CASES[0].text
        for mode in modes:
            if mode == "ai":
                continue   # skip AI — too expensive and non-deterministic
            fn = redact_token if mode == "token" else redact_fake
            print(dim(f"    {mode} (3 runs) …"), end="", flush=True)
            stable, msg = test_longitudinal(fn, sample_text)
            ext.longitudinal[mode] = (stable, msg)
            print(dim(" done"))

    if "corrections" in suites:
        ext.corrections = summarise_corrections()

    return ext


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


def print_extended_report(ext: ExtendedResults) -> None:
    w = 72
    print()
    print(bold("━" * w))
    print(bold("  ZebraRedact — Extended Evaluation Suite"))
    print(bold("━" * w))

    # ── Coreference Consistency ───────────────────────────────────────────────
    if ext.consistency:
        print()
        print(bold("  SUITE 1 — Coreference Consistency"))
        print(dim("  Same entity in multiple surface forms — all must be removed"))
        print()
        by_case: dict[str, list[ConsistencyResult]] = {}
        for r in ext.consistency:
            by_case.setdefault(r.case.name, []).append(r)
        for case_name, results in by_case.items():
            print(f"  {cyan(case_name)}")
            for r in results:
                n_removed = sum(r.form_audit.values())
                n_total   = len(r.form_audit)
                all_ok    = n_removed == n_total
                status    = green(f"✓ {n_removed}/{n_total}") if all_ok else red(f"✗ {n_removed}/{n_total}")
                print(f"    {bold(f'{r.mode.upper():<8}')} Forms removed: {status}")
                for form, removed in r.form_audit.items():
                    icon = green("✓") if removed else red("✗")
                    print(f"             {icon} {dim(repr(form))}")
                if r.assessment:
                    print(f"           → {dim(textwrap.shorten(r.assessment, 62))}")
            print()

    # ── Adversarial Evasion ───────────────────────────────────────────────────
    if ext.adversarial:
        print(bold("  SUITE 2 — Adversarial Evasion + Re-Identification"))
        print(dim("  PII formatted to defeat pattern matching; adversary re-ID test"))
        print()
        for cr in ext.adversarial:
            print(f"  {cyan(cr.case.name)}")
            print(dim(f"  {cr.case.description}"))
            for mode, mr in cr.modes.items():
                reid = ext.reid_map.get(cr.case.name, {}).get(mode, (False, ""))
                could_id, identified_as = reid
                reid_str = red("re-identifiable") if could_id else green("not re-identifiable")
                print(f"    {bold(f'{mode.upper():<8}')} Recall: {recall_bar(mr.recall, 12)}  |  {reid_str}")
                if could_id and identified_as:
                    print(f"             → {dim(textwrap.shorten(identified_as, 58))}")
            print()

    # ── Domain Blind Spots ────────────────────────────────────────────────────
    if ext.domain:
        print(bold("  SUITE 3 — Domain Blind Spots"))
        print(dim("  Document types underrepresented in the base test corpus"))
        print()
        for cr in ext.domain:
            print(f"  {cyan(cr.case.name)} {dim('[' + cr.case.category + ']')}")
            for mode, mr in cr.modes.items():
                print(f"    {bold(f'{mode.upper():<8}')} Recall: {recall_bar(mr.recall, 12)}  Risk: {risk_badge(mr.risk_level)}")
                if mr.semantic_note:
                    print(f"             {dim(textwrap.shorten(mr.semantic_note, 60))}")
            print()

    # ── Cross-Reference Attack ────────────────────────────────────────────────
    if ext.crossref:
        print(bold("  SUITE 4 — Cross-Reference Attack"))
        print(dim("  Two documents safe alone — combined they re-identify"))
        print()
        by_pair: dict[str, list[CrossRefResult]] = {}
        for r in ext.crossref:
            by_pair.setdefault(r.pair.name, []).append(r)
        for pair_name, results in by_pair.items():
            print(f"  {cyan(pair_name)}")
            for r in results:
                icon = red("✗ LEAKED") if r.reidentified else green("✓ SAFE  ")
                print(f"    {bold(f'{r.mode.upper():<8}')} {icon}")
                if r.reidentified and r.what_revealed:
                    print(f"             → {dim(textwrap.shorten(r.what_revealed, 58))}")
            print()

    # ── Longitudinal Stability ────────────────────────────────────────────────
    if ext.longitudinal:
        print(bold("  SUITE 5 — Longitudinal Stability"))
        print(dim("  Same input → identical output across multiple runs"))
        print()
        for mode, (stable, msg) in ext.longitudinal.items():
            icon = green("✓ STABLE  ") if stable else red("✗ UNSTABLE")
            print(f"  {bold(f'{mode.upper():<10}')} {icon}  {dim(msg)}")
        print()

    # ── User Correction Log ───────────────────────────────────────────────────
    if ext.corrections:
        c = ext.corrections
        print(bold("  SUITE 6 — User Correction Log"))
        print(dim("  False positives / negatives logged during real use"))
        print()
        total = c.get("total", 0)
        if total == 0:
            print(dim("  No corrections logged yet."))
        else:
            fp = c.get("false_positive", 0)
            fn = c.get("false_negative", 0)
            print(f"  Total: {bold(str(total))}   "
                  f"Over-redacted: {yellow(str(fp))}   "
                  f"Missed: {red(str(fn))}")
            if c.get("examples"):
                print(f"\n  Last {len(c['examples'])} corrections:")
                for ex in c["examples"]:
                    tp = ex.get("correction_type", "?")
                    ot = textwrap.shorten(ex.get("original_text", ""), 35)
                    ct = textwrap.shorten(ex.get("corrected_to", ""), 20)
                    print(f"    {dim(ex.get('ts', '')[:10])}  {tp:16}  {ot!r} → {ct!r}")
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
    ALL_SUITES = ["consistency", "adversarial", "domain", "crossref", "longitudinal", "corrections"]

    parser = argparse.ArgumentParser(description="ZebraRedact accuracy evaluation")
    parser.add_argument("--mode", choices=["token", "fake", "ai"],
                        help="Run only this mode (default: all three)")
    parser.add_argument("--case", metavar="NAME",
                        help="Run only base cases whose name contains NAME (case-insensitive)")
    parser.add_argument("--suite",
                        choices=["base"] + ALL_SUITES + ["all"],
                        default="base",
                        help=(
                            "Which evaluation suite to run (default: base). "
                            "'base' = 9 core documents. "
                            "'all' = every extended suite. "
                            "Individual: consistency | adversarial | domain | crossref | "
                            "longitudinal | corrections"
                        ))
    parser.add_argument("--json", action="store_true",
                        help="Save machine-readable results to eval/reports/")
    parser.add_argument("--show-redacted", action="store_true",
                        help="Print the full redacted text for each case/mode (base suite only)")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print(red("Error: ANTHROPIC_API_KEY environment variable not set."))
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)
    modes = [args.mode] if args.mode else ["token", "fake", "ai"]

    # ── Base suite ────────────────────────────────────────────────────────────
    if args.suite == "base":
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

    # ── Extended suites ───────────────────────────────────────────────────────
    else:
        suites = ALL_SUITES if args.suite == "all" else [args.suite]

        n_docs = (
            len(CONSISTENCY_CASES) * len(modes) * ("consistency" in suites) +
            len(ADVERSARIAL_CASES) * ("adversarial" in suites) +
            len(DOMAIN_CASES) * ("domain" in suites) +
            len(CROSSREF_PAIRS) * len(modes) * ("crossref" in suites)
        )
        print(bold(f"\n  Extended suite(s): {', '.join(suites)}"))
        print(dim(f"  Modes: {', '.join(modes)}  |  ~{n_docs} redaction calls + audit calls"))
        print(dim("  Expect 1–5 min depending on suites selected.\n"))

        ext = run_extended(client, suites, modes)
        print_extended_report(ext)

        if args.json:
            os.makedirs("eval/reports", exist_ok=True)
            ts = time.strftime("%Y%m%d_%H%M%S")
            path = f"eval/reports/{ts}_extended.json"
            out: dict = {"suites": suites, "modes": modes}
            if ext.consistency:
                out["consistency"] = [
                    {"case": r.case.name, "mode": r.mode,
                     "form_audit": r.form_audit, "assessment": r.assessment}
                    for r in ext.consistency
                ]
            if ext.adversarial:
                out["adversarial"] = [
                    {"case": cr.case.name, "modes": {
                        mode: {
                            "recall": round(mr.recall, 3),
                            "risk": mr.risk_level,
                            "reid": ext.reid_map.get(cr.case.name, {}).get(mode, (False, ""))[0],
                        } for mode, mr in cr.modes.items()
                    }} for cr in ext.adversarial
                ]
            if ext.domain:
                out["domain"] = [
                    {"case": cr.case.name, "modes": {
                        mode: {"recall": round(mr.recall, 3), "risk": mr.risk_level}
                        for mode, mr in cr.modes.items()
                    }} for cr in ext.domain
                ]
            if ext.crossref:
                out["crossref"] = [
                    {"pair": r.pair.name, "mode": r.mode,
                     "reidentified": r.reidentified, "what_revealed": r.what_revealed}
                    for r in ext.crossref
                ]
            if ext.longitudinal:
                out["longitudinal"] = {
                    mode: {"stable": stable, "message": msg}
                    for mode, (stable, msg) in ext.longitudinal.items()
                }
            if ext.corrections:
                out["corrections"] = ext.corrections
            with open(path, "w") as f:
                json.dump(out, f, indent=2, ensure_ascii=False)
            print(dim(f"\n  JSON saved → {path}"))


if __name__ == "__main__":
    main()
