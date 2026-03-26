interface Props {
  onStart: () => void
}

export function Landing({ onStart }: Props) {
  return (
    <div className="landing">

      {/* ── Nav ── */}
      <nav className="lnav">
        <span className="lnav-logo">ZebraRedact</span>
        <button className="btn-primary" onClick={onStart}>Start redacting</button>
      </nav>

      {/* ── Hero ── */}
      <section className="hero">
        <p className="hero-eyebrow">Free · No signup · Runs in your browser</p>
        <h1 className="hero-h1">Redact before you send.<br />Restore when you're done.</h1>
        <p className="hero-sub">
          Paste sensitive text, hide what matters with a click, send the safe version to any AI.
          When the response comes back, one more click restores every original value inline.
        </p>
        <button className="hero-cta" onClick={onStart}>
          Start redacting →
        </button>
      </section>

      {/* ── Demo GIF ── */}
      <section className="demo-section">
        <div className="demo-gif-wrap">
          <img src="/demo.gif" alt="ZebraRedact workflow demo" />
        </div>
      </section>

      {/* ── Steps ── */}
      <section className="steps-section">
        <h2 className="steps-heading">How it works</h2>
        <div className="steps">
          <div className="step">
            <div className="step-num">1</div>
            <h3 className="step-title">Select &amp; redact</h3>
            <p className="step-body">
              Paste or type your text. Highlight any sensitive part and click
              the floating <em>Redact</em> button. It becomes a black bar
              — invisible to the AI, reversible by you.
            </p>
          </div>
          <div className="step">
            <div className="step-num">2</div>
            <h3 className="step-title">Send to AI</h3>
            <p className="step-body">
              Hit <em>Send to ChatGPT</em> (or Claude, Perplexity, Grok).
              The prompt is copied with a safety instruction that tells the
              AI to preserve every token unchanged in its reply.
            </p>
          </div>
          <div className="step">
            <div className="step-num">3</div>
            <h3 className="step-title">Restore</h3>
            <p className="step-body">
              Paste the AI's response back. Tokens render as black bars
              automatically. Click <em>Unredact all</em> to swap every
              token back to the original value — right inline.
            </p>
          </div>
        </div>
      </section>

      {/* ── Privacy ── */}
      <section className="privacy-section">
        <div className="privacy-card">
          <h2 className="privacy-heading">Your data stays in your browser</h2>
          <p className="privacy-body">
            ZebraRedact makes zero network calls of its own. Token mappings
            live in your browser's localStorage and are never sent anywhere.
            When you use the Send button, only the already-redacted text
            (tokens, not originals) reaches the AI service.
          </p>
          <ul className="privacy-list">
            <li>No account, no signup, no tracking</li>
            <li>Works entirely offline after first load</li>
            <li>Open source — inspect every line</li>
          </ul>
        </div>
      </section>

      {/* ── Footer CTA ── */}
      <section className="footer-cta">
        <h2 className="footer-cta-h2">Ready to protect your prompts?</h2>
        <button className="hero-cta" onClick={onStart}>Start redacting →</button>
      </section>

      <footer className="lfooter">
        <span>© 2025 ZebraRedact</span>
      </footer>

    </div>
  )
}
