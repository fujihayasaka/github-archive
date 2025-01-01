/**
 * Compares two date strings.
 * @param date1 The first date string to compare.
 * @param date2 The second date string to compare.
 * @returns A negative number if date1 is earlier than date2, a positive number if date1 is later than date2, and 0 if they are equal.
 */
export function compareDateStrings(date1: string, date2: string): number {
  return new Date(date1).getTime() - new Date(date2).getTime()
}
