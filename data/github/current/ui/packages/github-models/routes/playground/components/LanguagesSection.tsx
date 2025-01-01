import {testIdProps} from '@github-ui/test-id-props'
import {useState} from 'react'
import {Box} from '@primer/react'
import {EllipsisIcon} from '@primer/octicons-react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'

interface LanguagesSectionProps {
  languages: string[]
  headingLevel?: 'h2' | 'h3'
}

export function LanguagesSection({languages, headingLevel = 'h3'}: LanguagesSectionProps) {
  const [languagesIsOpen, setLanguagesIsOpen] = useState(false)
  const shouldTruncateLanguages = languages.length > 12
  let languagesString: string | undefined
  const languageNames = new Intl.DisplayNames(['en'], {type: 'language'})
  const formattedLanguages = languages.map(language => languageNames.of(language))

  if (formattedLanguages.length === 1) {
    languagesString = formattedLanguages[0]
  } else if (shouldTruncateLanguages && !languagesIsOpen) {
    languagesString = formattedLanguages.slice(0, 12).join(', ')
  } else {
    const languagesButLast = formattedLanguages.slice(0, formattedLanguages.length - 1).join(', ')
    languagesString = `${languagesButLast}, and ${formattedLanguages[formattedLanguages.length - 1]}`
  }

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: 2,
      }}
    >
      <SidebarHeading htmlTag={headingLevel} title="Languages" count={languages.length} />
      <div {...testIdProps('languages')}>
        {languagesString}{' '}
        {shouldTruncateLanguages && !languagesIsOpen && (
          <>
            {' '}
            <Box
              as="button"
              aria-label="Reveal all languages"
              sx={{color: 'fg.muted', display: 'inline', cursor: 'pointer', border: 0, bg: 'transparent'}}
              onClick={() => setLanguagesIsOpen(true)}
            >
              <EllipsisIcon />
            </Box>
          </>
        )}
      </div>
    </Box>
  )
}
