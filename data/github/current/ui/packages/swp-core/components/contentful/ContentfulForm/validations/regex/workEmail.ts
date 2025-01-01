// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
const PERSONAL_DOMAINS = [
  'gmail',
  'yahoo',
  'hotmail',
  'aol',
  'msn',
  'orange',
  'comcast',
  'live',
  'outlook',
  'yandex',
  'me',
  'icloud',
  'verizon',
  'fastmail',
]

const TOP_LEVEL_DOMAINS = ['com', 'co\\.uk', 'fr', 'net', 'fm', 'ru']

// Checks for email addresses that do not end with certain personal domains and top-level domains.
export const EMAIL_PERSONAL_DOMAIN_REGEX = new RegExp(
  `@(${PERSONAL_DOMAINS.join('|')})\\.(${TOP_LEVEL_DOMAINS.join('|')})$`,
)
