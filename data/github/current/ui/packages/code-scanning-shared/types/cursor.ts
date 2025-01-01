export type Cursor =
  | {
      before: string
    }
  | {
      after: string
    }

export function parseCursor(params: URLSearchParams): Cursor | null {
  const after = params.get('after')
  if (after) {
    return {after}
  }

  const before = params.get('before')
  if (before) {
    return {before}
  }

  return null
}

export function serializeCursor(cursor: Cursor | null, params: URLSearchParams): void {
  if (cursor && 'before' in cursor) {
    params.set('before', cursor.before)
    params.delete('after')
  } else if (cursor && 'after' in cursor) {
    params.set('after', cursor.after)
    params.delete('before')
  } else {
    params.delete('before')
    params.delete('after')
  }
}
