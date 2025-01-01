export function diffContent(originalPrefix: string, currentPrefix: string): {added: string; removed: number} {
  // We know there's a difference somewhere. Start from the end and go back until we find the start of it.
  let i = originalPrefix.length
  while (originalPrefix.substring(0, i) !== currentPrefix.substring(0, i)) {
    i--
    if (i < 0) {
      break
    }
  }

  return {added: originalPrefix.slice(i), removed: currentPrefix.length - i}
}
