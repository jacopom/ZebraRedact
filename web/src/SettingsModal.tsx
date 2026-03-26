import { useState } from 'react'
import { LLM_PLATFORMS, LLMPlatform } from './llm'
import { clearAllTokens, tokenCount } from './tokenStore'

export type Theme = 'system' | 'light' | 'dark'

interface Props {
  defaultLLM: LLMPlatform
  onChangeLLM: (llm: LLMPlatform) => void
  theme: Theme
  onChangeTheme: (t: Theme) => void
  onClose: () => void
}

export function SettingsModal({ defaultLLM, onChangeLLM, theme, onChangeTheme, onClose }: Props) {
  const [count, setCount] = useState(tokenCount)

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <h2>Settings</h2>

        <div className="setting-row">
          <div className="setting-label">Appearance</div>
          <select
            className="setting-select"
            value={theme}
            onChange={e => onChangeTheme(e.target.value as Theme)}
          >
            <option value="system">System default</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </div>

        <div className="setting-row">
          <div className="setting-label">Default AI assistant</div>
          <select
            className="setting-select"
            value={defaultLLM}
            onChange={e => onChangeLLM(e.target.value as LLMPlatform)}
          >
            {Object.entries(LLM_PLATFORMS).map(([key, llm]) => (
              <option key={key} value={key}>{llm.name}</option>
            ))}
          </select>
        </div>

        <div className="setting-row">
          <div className="setting-label">Stored tokens</div>
          <div className="setting-token-row">
            <span className="setting-token-count">{count} token{count !== 1 ? 's' : ''} in memory</span>
            <button
              className="btn-ghost btn-sm"
              onClick={() => { clearAllTokens(); setCount(0) }}
              disabled={count === 0}
            >
              Clear
            </button>
          </div>
          <p className="setting-hint">
            Tokens are stored locally in your browser so you can unredact LLM responses.
            Clear them when you start a new session.
          </p>
        </div>

        <button className="btn-primary modal-close" onClick={onClose}>Done</button>
      </div>
    </div>
  )
}
