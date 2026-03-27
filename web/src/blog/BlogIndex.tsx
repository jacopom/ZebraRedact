import { useSEO } from '../useSEO'
import { posts } from './posts'

interface Props {
  onNavigate: (path: string) => void
  onStart: () => void
}

export function BlogIndex({ onNavigate, onStart }: Props) {
  useSEO({
    title: 'Blog — ZebraRedact',
    description: 'Guides on protecting sensitive data, PII, and privacy when using AI tools like ChatGPT, Claude, and Gemini.',
    canonical: 'https://zebraredact.com/blog',
  })

  return (
    <div className="landing">
      <nav className="lnav">
        <a className="lnav-logo" href="/" onClick={e => { e.preventDefault(); onNavigate('/') }}>
          ZebraRedact
        </a>
        <button className="btn-primary" onClick={onStart}>Start redacting</button>
      </nav>

      <section className="blog-hero">
        <h1 className="blog-hero-h1">Blog</h1>
        <p className="blog-hero-sub">
          Guides on protecting sensitive data when using AI tools like ChatGPT, Claude, and Gemini.
        </p>
      </section>

      <section className="blog-list">
        {posts.map(post => (
          <a
            key={post.slug}
            className="blog-card"
            href={`/blog/${post.slug}`}
            onClick={e => { e.preventDefault(); onNavigate(`/blog/${post.slug}`) }}
          >
            <div className="blog-card-meta">
              <time>{new Date(post.date).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</time>
              <span>{post.readTime}</span>
            </div>
            <h2 className="blog-card-title">{post.title}</h2>
            <p className="blog-card-desc">{post.description}</p>
          </a>
        ))}
      </section>

      <footer className="lfooter">
        <span>&copy; 2025 ZebraRedact</span>
      </footer>
    </div>
  )
}
