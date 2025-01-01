export function formatDate(date: Date): string {
  const clientLocale = navigator.language

  // Format the date to "June 30, 2025" style
  const options: Intl.DateTimeFormatOptions = {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }

  return new Intl.DateTimeFormat(clientLocale, options).format(date)
}
