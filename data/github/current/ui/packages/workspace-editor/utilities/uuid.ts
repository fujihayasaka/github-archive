// Generate V4 UUID using a cryptographically secure random number generator.
export function uuid(): string {
  return crypto.randomUUID()
}
