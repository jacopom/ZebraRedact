import { useRef, useState, useCallback, useEffect } from 'react'
import { Editor, EditorHandle } from './Editor'
import { SettingsModal, Theme } from './SettingsModal'
import { Landing } from './Landing'
import { BlogIndex } from './blog/BlogIndex'
import { BlogPost } from './blog/BlogPost'
import { buildPrompt, LLM_PLATFORMS, LLMPlatform } from './llm'

const DEFAULT_LLM_KEY = 'zr:defaultLLM'
const SEEN_LANDING_KEY = 'zr:seenLanding'
const THEME_KEY = 'zr:theme'

function applyTheme(t: Theme) {
  if (t === 'system') {
    document.documentElement.removeAttribute('data-theme')
  } else {
    document.documentElement.setAttribute('data-theme', t)
  }
}

function syncCopy(text: string) {
  const ta = document.createElement('textarea')
  ta.value = text
  ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px'
  document.body.appendChild(ta)
  ta.select()
  document.execCommand('copy')
  document.body.removeChild(ta)
  navigator.clipboard?.writeText(text).catch(() => {})
}

function usePath() {
  const [path, setPath] = useState(window.location.pathname)
  useEffect(() => {
    const onPop = () => setPath(window.location.pathname)
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])
  const navigate = useCallback((to: string) => {
    window.history.pushState(null, '', to)
    setPath(to)
    window.scrollTo(0, 0)
  }, [])
  return { path, navigate }
}

export default function App() {
  const { path, navigate } = usePath()
  // ALL hooks must come before any conditional return
  const [showEditor, setShowEditor] = useState(() => !!localStorage.getItem(SEEN_LANDING_KEY))
  const editorRef = useRef<EditorHandle>(null)
  const [hasTokens, setHasTokens] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [showLLMMenu, setShowLLMMenu] = useState(false)
  const [showPanel, setShowPanel] = useState(false)
  const [panelPrompt, setPanelPrompt] = useState('')
  const [copied, setCopied] = useState(false)
  const [defaultLLM, setDefaultLLM] = useState<LLMPlatform>(() => {
    return (localStorage.getItem(DEFAULT_LLM_KEY) as LLMPlatform) ?? 'chatgpt'
  })
  const [theme, setTheme] = useState<Theme>(() => {
    return (localStorage.getItem(THEME_KEY) as Theme) ?? 'system'
  })

  const handleStart = useCallback(() => {
    localStorage.setItem(SEEN_LANDING_KEY, '1')
    setShowEditor(true)
    navigate('/')
  }, [navigate])

  const buildCurrentPrompt = useCallback(() => {
    const text = editorRef.current?.getRedactedText() ?? ''
    return text.trim() ? buildPrompt(text) : ''
  }, [])

  const sendToLLM = useCallback((platform: LLMPlatform) => {
    const prompt = buildCurrentPrompt()
    if (!prompt) return
    syncCopy(prompt)
    window.open(LLM_PLATFORMS[platform].url, '_blank')
    setShowLLMMenu(false)
  }, [buildCurrentPrompt])

  const openPanel = useCallback(() => {
    const prompt = buildCurrentPrompt()
    if (!prompt) return
    setPanelPrompt(prompt)
    setShowPanel(true)
    setShowLLMMenu(false)
  }, [buildCurrentPrompt])

  const handlePanelCopy = useCallback(async () => {
    try { await navigator.clipboard.writeText(panelPrompt) }
    catch { syncCopy(panelPrompt) }
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }, [panelPrompt])

  const changeLLM = useCallback((llm: LLMPlatform) => {
    setDefaultLLM(llm)
    localStorage.setItem(DEFAULT_LLM_KEY, llm)
  }, [])

  const changeTheme = useCallback((t: Theme) => {
    setTheme(t)
    localStorage.setItem(THEME_KEY, t)
    applyTheme(t)
  }, [])

  useEffect(() => { applyTheme(theme) }, []) // apply persisted theme on mount

  useEffect(() => {
    if (!showLLMMenu) return
    const close = () => setShowLLMMenu(false)
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [showLLMMenu])

  // Blog routes
  if (path === '/blog') return <BlogIndex onNavigate={navigate} onStart={handleStart} />
  if (path.startsWith('/blog/')) {
    const slug = path.replace('/blog/', '')
    return <BlogPost slug={slug} onNavigate={navigate} onStart={handleStart} />
  }

  // Landing page — shown once, skipped on return visits
  if (!showEditor) return <Landing onStart={handleStart} onNavigate={navigate} />

  return (
    <div className="app">
      <header className="header">
        <button className="logo logo--btn" onClick={() => { setShowEditor(false); navigate('/') }}>ZebraRedact</button>
        <div className="header-actions">
          {hasTokens && (
            <button className="btn-ghost" onClick={() => editorRef.current?.unredactAll()}>
              Unredact all
            </button>
          )}
          <button className="btn-ghost icon-btn" onClick={() => setShowSettings(true)} title="Settings">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M8 10a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z" stroke="currentColor" strokeWidth="1.5"/>
              <path d="M13.3 6.6a1.3 1.3 0 0 0 .26-1.44l-.53-1.06a1.3 1.3 0 0 0-1.38-.7l-.9.18a5.1 5.1 0 0 0-.82-.47l-.22-.88A1.3 1.3 0 0 0 8.45 2h-1.1a1.3 1.3 0 0 0-1.26.99l-.22.88c-.3.13-.57.29-.82.47l-.9-.18a1.3 1.3 0 0 0-1.38.7l-.53 1.06a1.3 1.3 0 0 0 .26 1.44l.65.6a5 5 0 0 0 0 .94l-.65.6a1.3 1.3 0 0 0-.26 1.44l.53 1.06c.27.54.85.84 1.38.7l.9-.18c.25.18.52.34.82.47l.22.88c.17.63.74 1.03 1.26.99h1.1c.52.04 1.09-.36 1.26-.99l.22-.88c.3-.13.57-.29.82-.47l.9.18c.53.14 1.11-.16 1.38-.7l.53-1.06a1.3 1.3 0 0 0-.26-1.44l-.65-.6c.04-.31.06-.63 0-.94l.65-.6Z" stroke="currentColor" strokeWidth="1.5"/>
            </svg>
          </button>
        </div>
      </header>

      <main className="main">
        <Editor ref={editorRef} onTokensChange={setHasTokens} />
      </main>

      <footer className="footer">
        <span className="send-hint">
          Copies redacted text to clipboard · paste when {LLM_PLATFORMS[defaultLLM].name} opens
        </span>
        <div className="send-group" onMouseDown={e => e.stopPropagation()}>
          <button className="btn-primary send-main" onClick={() => sendToLLM(defaultLLM)}>
            Send to {LLM_PLATFORMS[defaultLLM].name}
          </button>
          <button
            className="btn-primary send-arrow"
            onClick={() => setShowLLMMenu(v => !v)}
            title="Options"
          >
            <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth="1.5">
              <path d="M1 3l4 4 4-4"/>
            </svg>
          </button>
          {showLLMMenu && (
            <div className="llm-menu">
              {(Object.keys(LLM_PLATFORMS) as LLMPlatform[]).map(key => (
                <button
                  key={key}
                  className={`llm-menu-item ${key === defaultLLM ? 'active' : ''}`}
                  onClick={() => { changeLLM(key); sendToLLM(key) }}
                >
                  {LLM_PLATFORMS[key].name}
                </button>
              ))}
              <div className="llm-menu-divider" />
              <button className="llm-menu-item llm-menu-item-muted" onClick={openPanel}>
                Preview prompt
              </button>
            </div>
          )}
        </div>
      </footer>

      {showPanel && (
        <div className="modal-overlay" onClick={() => setShowPanel(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-panel-header">
              <h2>Prompt</h2>
              <button className="btn-ghost btn-sm" onClick={() => setShowPanel(false)}>✕</button>
            </div>
            <textarea
              className="send-panel-textarea"
              readOnly
              value={panelPrompt}
              onClick={e => (e.target as HTMLTextAreaElement).select()}
            />
            <div className="send-panel-actions">
              <button className="btn-primary modal-close-btn" onClick={handlePanelCopy}>
                {copied ? '✓ Copied' : 'Copy'}
              </button>
            </div>
          </div>
        </div>
      )}

      {showSettings && (
        <SettingsModal
          defaultLLM={defaultLLM}
          onChangeLLM={changeLLM}
          theme={theme}
          onChangeTheme={changeTheme}
          onClose={() => setShowSettings(false)}
        />
      )}
    </div>
  )
}
