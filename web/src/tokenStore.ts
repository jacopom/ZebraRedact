const PREFIX = 'zr:'

export function generateToken(): string {
  const id = Math.random().toString(36).substring(2, 6).toUpperCase()
  return `[ITEM_${id}]`
}

export function storeToken(token: string, original: string): void {
  localStorage.setItem(PREFIX + token, original)
}

export function getOriginal(token: string): string | null {
  return localStorage.getItem(PREFIX + token)
}

export function clearAllTokens(): void {
  Object.keys(localStorage)
    .filter(k => k.startsWith(PREFIX))
    .forEach(k => localStorage.removeItem(k))
}

export function tokenCount(): number {
  return Object.keys(localStorage).filter(k => k.startsWith(PREFIX)).length
}

// Matches [WORD_XXXX] — covers both web tokens ([ITEM_A1B2]) and desktop tokens ([EMAIL_A1B2])
export const TOKEN_PATTERN = /\[[A-Z]+_[A-Z0-9]{4}\]/g
