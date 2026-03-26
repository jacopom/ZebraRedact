import { forwardRef, useRef, useCallback, useImperativeHandle, useEffect, useState } from 'react'
import { generateToken, storeToken, getOriginal, TOKEN_PATTERN } from './tokenStore'

export interface EditorHandle {
  getRedactedText(): string
  unredactAll(): void
}

interface FloatBtn {
  x: number
  y: number
  range: Range
  selectedText: string
  allRanges: Range[]
}

interface Props {
  onTokensChange: (hasTokens: boolean) => void
}

// CSS Highlight API helpers (not available in all browsers — degrade gracefully)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cssHighlights = (CSS as any).highlights as Map<string, unknown> | undefined

function applyOccurrenceHighlight(ranges: Range[]) {
  if (!cssHighlights) return
  if (ranges.length === 0) { cssHighlights.delete('zr-occ'); return }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  cssHighlights.set('zr-occ', new (window as any).Highlight(...ranges))
}

function clearOccurrenceHighlight() {
  cssHighlights?.delete('zr-occ')
}

function findAllOccurrences(editor: HTMLDivElement, text: string): Range[] {
  if (!text) return []
  const lower = text.toLowerCase()
  const ranges: Range[] = []
  const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      // Skip text nodes inside token bars
      return (node.parentElement?.classList.contains('token-bar'))
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT
    },
  })
  let node: Text | null
  while ((node = walker.nextNode() as Text | null)) {
    const content = node.textContent ?? ''
    let idx = 0
    while (idx < content.length) {
      const pos = content.toLowerCase().indexOf(lower, idx)
      if (pos === -1) break
      const range = document.createRange()
      range.setStart(node, pos)
      range.setEnd(node, pos + text.length)
      ranges.push(range)
      idx = pos + text.length
    }
  }
  return ranges
}

function makeTokenBar(token: string, original: string): HTMLSpanElement {
  const span = document.createElement('span')
  span.className = 'token-bar'
  span.dataset.token = token
  span.contentEditable = 'false'
  span.title = 'Click to unredact'
  span.style.width = `${Math.max(2, original.length * 0.55)}ch`
  return span
}

export const Editor = forwardRef<EditorHandle, Props>(({ onTokensChange }, ref) => {
  const divRef = useRef<HTMLDivElement>(null)
  const [floatBtn, setFloatBtn] = useState<FloatBtn | null>(null)

  const syncTokenState = useCallback(() => {
    const div = divRef.current
    if (!div) return
    onTokensChange(div.querySelectorAll('.token-bar').length > 0)
  }, [onTokensChange])

  // Track selection changes (keyboard + mouse)
  useEffect(() => {
    const onSelectionChange = () => {
      const sel = window.getSelection()
      if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
        clearOccurrenceHighlight()
        setFloatBtn(null)
        return
      }

      const range = sel.getRangeAt(0)
      const editor = divRef.current
      if (!editor || !editor.contains(range.commonAncestorContainer)) {
        clearOccurrenceHighlight()
        setFloatBtn(null)
        return
      }

      const text = range.toString().trim()
      if (!text) {
        clearOccurrenceHighlight()
        setFloatBtn(null)
        return
      }

      // Don't offer redact if selection overlaps existing token bars
      const frag = range.cloneContents()
      if (frag.querySelector('.token-bar')) {
        clearOccurrenceHighlight()
        setFloatBtn(null)
        return
      }

      // Find all other occurrences and highlight them
      const allRanges = findAllOccurrences(editor, text)
      // Exclude the one the user selected (filter by approximate position)
      const occurrencesOnly = allRanges.filter(r => {
        const selRange = range.cloneRange()
        return r.compareBoundaryPoints(Range.START_TO_START, selRange) !== 0 ||
               r.compareBoundaryPoints(Range.END_TO_END, selRange) !== 0
      })
      applyOccurrenceHighlight(occurrencesOnly)

      const rect = range.getBoundingClientRect()
      setFloatBtn({
        x: rect.left + rect.width / 2,
        y: rect.top,
        range: range.cloneRange(),
        selectedText: text,
        allRanges,
      })
    }

    document.addEventListener('selectionchange', onSelectionChange)
    return () => document.removeEventListener('selectionchange', onSelectionChange)
  }, [])

  const redactOne = useCallback(() => {
    if (!floatBtn) return
    const { range, selectedText } = floatBtn
    if (!selectedText) return

    const token = generateToken()
    storeToken(token, selectedText)
    range.deleteContents()
    range.insertNode(makeTokenBar(token, selectedText))

    window.getSelection()?.removeAllRanges()
    clearOccurrenceHighlight()
    setFloatBtn(null)
    syncTokenState()
  }, [floatBtn, syncTokenState])

  const redactAll = useCallback(() => {
    if (!floatBtn) return
    const { selectedText, allRanges } = floatBtn
    if (!selectedText || allRanges.length === 0) return

    // One shared token — all occurrences have the same original value
    const token = generateToken()
    storeToken(token, selectedText)

    // Process ranges in reverse document order so earlier ranges aren't invalidated
    const sorted = [...allRanges].sort((a, b) =>
      a.compareBoundaryPoints(Range.END_TO_START, b) > 0 ? -1 : 1
    )
    sorted.forEach(r => {
      r.deleteContents()
      r.insertNode(makeTokenBar(token, selectedText))
    })

    window.getSelection()?.removeAllRanges()
    clearOccurrenceHighlight()
    setFloatBtn(null)
    syncTokenState()
  }, [floatBtn, syncTokenState])

  const handleClick = useCallback((e: React.MouseEvent) => {
    const target = e.target as HTMLElement
    if (!target.classList.contains('token-bar')) return

    const token = target.dataset.token
    if (!token) return
    const original = getOriginal(token) ?? token
    target.replaceWith(document.createTextNode(original))
    syncTokenState()
  }, [syncTokenState])

  const handlePaste = useCallback((e: React.ClipboardEvent) => {
    e.preventDefault()
    const text = e.clipboardData.getData('text/plain')
    if (!text) return

    // Build HTML, converting any token patterns to black bar spans
    const regex = new RegExp(TOKEN_PATTERN.source, 'g')
    const parts: string[] = []
    let lastIndex = 0
    let match: RegExpExecArray | null

    while ((match = regex.exec(text)) !== null) {
      if (match.index > lastIndex) {
        parts.push(escapeHtml(text.slice(lastIndex, match.index)))
      }
      const token = match[0]
      const original = getOriginal(token)
      const width = original ? `${Math.max(2, original.length * 0.55)}ch` : '6ch'
      parts.push(
        `<span class="token-bar" contenteditable="false" data-token="${token}" style="width:${width}" title="Click to unredact"></span>`
      )
      lastIndex = match.index + match[0].length
    }

    if (lastIndex < text.length) {
      parts.push(escapeHtml(text.slice(lastIndex)))
    }

    const html = parts.join('').replace(/\n/g, '<br>')

    const sel = window.getSelection()
    if (!sel || sel.rangeCount === 0) return

    const range = sel.getRangeAt(0)
    range.deleteContents()
    const frag = range.createContextualFragment(html)
    range.insertNode(frag)
    range.collapse(false)
    sel.removeAllRanges()
    sel.addRange(range)
    syncTokenState()
  }, [syncTokenState])

  useImperativeHandle(ref, () => ({
    getRedactedText() {
      const div = divRef.current
      if (!div) return ''
      return extractText(div).trim()
    },
    unredactAll() {
      const div = divRef.current
      if (!div) return
      const bars = Array.from(div.querySelectorAll<HTMLSpanElement>('.token-bar'))
      bars.forEach(bar => {
        const token = bar.dataset.token
        const original = token ? (getOriginal(token) ?? token) : '[REDACTED]'
        bar.replaceWith(document.createTextNode(original))
      })
      syncTokenState()
    },
  }))

  return (
    <>
      <div
        ref={divRef}
        className="editor"
        contentEditable
        suppressContentEditableWarning
        onClick={handleClick}
        onPaste={handlePaste}
        data-placeholder="Paste or type text here. Select any part and click Redact to mask it."
      />
      {floatBtn && (
        <div
          className="float-redact-group"
          style={{ left: floatBtn.x, top: floatBtn.y }}
        >
          <button
            className="float-redact-btn"
            onMouseDown={e => { e.preventDefault(); redactOne() }}
          >
            Redact
          </button>
          {floatBtn.allRanges.length > 1 && (
            <button
              className="float-redact-btn float-redact-btn-all"
              onMouseDown={e => { e.preventDefault(); redactAll() }}
            >
              Redact all ({floatBtn.allRanges.length})
            </button>
          )}
        </div>
      )}
    </>
  )
})

Editor.displayName = 'Editor'

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function extractText(node: Node): string {
  if (node.nodeType === Node.TEXT_NODE) {
    return node.textContent ?? ''
  }
  if (node instanceof HTMLElement) {
    if (node.classList.contains('token-bar')) {
      return node.dataset.token ?? '[REDACTED]'
    }
    if (node.tagName === 'BR') return '\n'

    const inner = Array.from(node.childNodes).map(extractText).join('')
    // Block-level elements produce a newline after their content
    if (['DIV', 'P'].includes(node.tagName)) {
      return inner + '\n'
    }
    return inner
  }
  return ''
}
