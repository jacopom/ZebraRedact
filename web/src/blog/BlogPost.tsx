import { useSEO } from '../useSEO'
import { posts } from './posts'

interface Props {
  slug: string
  onNavigate: (path: string) => void
  onStart: () => void
}

function renderMarkdown(content: string) {
  const lines = content.trim().split('\n')
  const elements: JSX.Element[] = []
  let i = 0
  let key = 0

  while (i < lines.length) {
    const line = lines[i]

    // Headings
    if (line.startsWith('### ')) {
      elements.push(<h3 key={key++}>{renderInline(line.slice(4))}</h3>)
      i++
      continue
    }
    if (line.startsWith('## ')) {
      elements.push(<h2 key={key++}>{renderInline(line.slice(3))}</h2>)
      i++
      continue
    }

    // Blockquote
    if (line.startsWith('> ')) {
      const quoteLines: string[] = []
      while (i < lines.length && lines[i].startsWith('> ')) {
        quoteLines.push(lines[i].slice(2))
        i++
      }
      elements.push(
        <blockquote key={key++}>
          <p>{renderInline(quoteLines.join(' '))}</p>
        </blockquote>
      )
      continue
    }

    // Ordered list
    if (/^\d+\.\s/.test(line)) {
      const items: string[] = []
      while (i < lines.length && /^\d+\.\s/.test(lines[i])) {
        items.push(lines[i].replace(/^\d+\.\s/, ''))
        i++
      }
      elements.push(
        <ol key={key++}>
          {items.map((item, j) => <li key={j}>{renderInline(item)}</li>)}
        </ol>
      )
      continue
    }

    // Unordered list
    if (line.startsWith('- ')) {
      const items: string[] = []
      while (i < lines.length && lines[i].startsWith('- ')) {
        items.push(lines[i].slice(2))
        i++
      }
      elements.push(
        <ul key={key++}>
          {items.map((item, j) => <li key={j}>{renderInline(item)}</li>)}
        </ul>
      )
      continue
    }

    // Empty line
    if (line.trim() === '') {
      i++
      continue
    }

    // Paragraph — collect consecutive non-empty, non-special lines
    const paraLines: string[] = []
    while (
      i < lines.length &&
      lines[i].trim() !== '' &&
      !lines[i].startsWith('#') &&
      !lines[i].startsWith('> ') &&
      !lines[i].startsWith('- ') &&
      !/^\d+\.\s/.test(lines[i])
    ) {
      paraLines.push(lines[i])
      i++
    }
    if (paraLines.length > 0) {
      elements.push(<p key={key++}>{renderInline(paraLines.join(' '))}</p>)
    }
  }

  return elements
}

function renderInline(text: string): (string | JSX.Element)[] {
  const parts: (string | JSX.Element)[] = []
  // Match **bold**, *italic*, `code`, and [text](url)
  const regex = /\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|\[(.+?)\]\((.+?)\)/g
  let last = 0
  let match: RegExpExecArray | null
  let k = 0

  while ((match = regex.exec(text)) !== null) {
    if (match.index > last) {
      parts.push(text.slice(last, match.index))
    }
    if (match[1]) parts.push(<strong key={k++}>{match[1]}</strong>)
    else if (match[2]) parts.push(<em key={k++}>{match[2]}</em>)
    else if (match[3]) parts.push(<code key={k++}>{match[3]}</code>)
    else if (match[4] && match[5]) parts.push(<a key={k++} href={match[5]}>{match[4]}</a>)
    last = match.index + match[0].length
  }

  if (last < text.length) {
    parts.push(text.slice(last))
  }

  return parts
}

export function BlogPost({ slug, onNavigate, onStart }: Props) {
  const post = posts.find(p => p.slug === slug)

  useSEO({
    title: post ? `${post.title} — ZebraRedact` : 'Post Not Found — ZebraRedact',
    description: post?.description ?? 'ZebraRedact: redact sensitive data before using AI.',
    canonical: post ? `https://zebraredact.com/blog/${post.slug}` : undefined,
  })

  if (!post) {
    return (
      <div className="landing">
        <nav className="lnav">
          <a className="lnav-logo" href="/" onClick={e => { e.preventDefault(); onNavigate('/') }}>
            ZebraRedact
          </a>
          <button className="btn-primary" onClick={onStart}>Start redacting</button>
        </nav>
        <section className="blog-hero">
          <h1 className="blog-hero-h1">Post not found</h1>
          <a href="/blog" onClick={e => { e.preventDefault(); onNavigate('/blog') }} className="blog-back">
            &larr; Back to blog
          </a>
        </section>
      </div>
    )
  }

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: post.title,
    description: post.description,
    datePublished: post.date,
    publisher: { '@type': 'Organization', name: 'ZebraRedact', url: 'https://zebraredact.com' },
    mainEntityOfPage: `https://zebraredact.com/blog/${post.slug}`,
  }

  return (
    <div className="landing">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <nav className="lnav">
        <a className="lnav-logo" href="/" onClick={e => { e.preventDefault(); onNavigate('/') }}>
          ZebraRedact
        </a>
        <button className="btn-primary" onClick={onStart}>Start redacting</button>
      </nav>

      <article className="blog-article">
        <a href="/blog" onClick={e => { e.preventDefault(); onNavigate('/blog') }} className="blog-back">
          &larr; Back to blog
        </a>
        <div className="blog-article-meta">
          <time>{new Date(post.date).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</time>
          <span>{post.readTime}</span>
        </div>
        <h1 className="blog-article-title">{post.title}</h1>
        <div className="blog-article-body">
          {renderMarkdown(post.content)}
        </div>

        <div className="blog-cta-card">
          <h3>Protect your data when using AI</h3>
          <p>ZebraRedact lets you redact sensitive information before sending it to ChatGPT, Claude, or any AI tool. Free, no signup, runs entirely in your browser.</p>
          <button className="hero-cta" onClick={onStart}>Start redacting &rarr;</button>
        </div>
      </article>

      <footer className="lfooter">
        <span>&copy; 2025 ZebraRedact</span>
      </footer>
    </div>
  )
}
