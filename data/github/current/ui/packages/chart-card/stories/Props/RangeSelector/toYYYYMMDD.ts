/**
 * Format date to YYYY-MM-DD
 * Adapted from @smockle’s function in https://github.com/github/accessibility-scorecard/blob/9fe343a6ce78648ebda73d40187208901b3a0e16/.github/actions/get-linting-service-maps/src/getRemediationRequired.ts#L25-L32
 * @param date Date to format
 * @returns Date formatted as YYYY-MM-DD
 */
// eslint-disable-next-line filenames/match-regex
export function toYYYYMMDD(date: Date | number | undefined): string | undefined {
  if (!date) return
  return new Intl.DateTimeFormat('sv-SE', {timeZone: 'UTC'}).format(new Date(date))
}
