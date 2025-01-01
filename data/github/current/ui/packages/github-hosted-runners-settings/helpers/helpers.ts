export function isLatestVersion(name: string): boolean {
  return /Latest( \([\w.]+\))?/.test(name)
}
