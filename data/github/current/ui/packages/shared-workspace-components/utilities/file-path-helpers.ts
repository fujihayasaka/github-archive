// This accounts for file names and paths beginning with `.` which would otherwise get rendered as e.g.
// `github/workflows/main.yml.` instead of the proper `.github/workflows/main.yml`
export function rtlProofPath(filePath: string): string {
  // The unicode character below is a left-to-right mark (https://en.wikipedia.org/wiki/Left-to-right_mark)
  // which prevents the browser from rendering the string right-to-left as set by the CSS for the element
  // calling this function.
  return filePath.startsWith('.') ? `\u200E${filePath}` : filePath
}
