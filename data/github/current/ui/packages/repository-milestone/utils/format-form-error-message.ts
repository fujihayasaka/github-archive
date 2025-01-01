export function formatFormErrorMessage(errors: readonly Error[]): string {
  return errors
    .map(e => e.message)
    .filter(Boolean)
    .join(', ')
}
