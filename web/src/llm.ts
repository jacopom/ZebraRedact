export type LLMPlatform = 'chatgpt' | 'claude' | 'perplexity' | 'grok'

export const LLM_PLATFORMS: Record<LLMPlatform, { name: string; url: string }> = {
  chatgpt:    { name: 'ChatGPT',    url: 'https://chatgpt.com/' },
  claude:     { name: 'Claude',     url: 'https://claude.ai/new' },
  perplexity: { name: 'Perplexity', url: 'https://www.perplexity.ai/' },
  grok:       { name: 'Grok',       url: 'https://x.com/i/grok' },
}

export function buildPrompt(redactedText: string): string {
  return `[Context for AI model]
The text below contains privacy tokens in the format [TYPE_XXXX]. These tokens replace sensitive personal information. Please:
- Preserve all tokens exactly as written (e.g. [NAME_A1B2], [EMAIL_C3D4])
- Do not attempt to guess, infer, or restore the original values
- Include the tokens unchanged wherever that information would appear in your response

---

${redactedText}`
}
