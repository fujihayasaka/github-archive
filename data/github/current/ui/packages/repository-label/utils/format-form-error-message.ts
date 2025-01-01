export function formatFormErrorMessage(
  errors: ReadonlyArray<{
    readonly message: string
  }>,
): string {
  return errors
    .map(e => e.message.trim())
    .filter(Boolean)
    .join(', ')
}
