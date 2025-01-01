import {Heading, Label, ThemeProvider} from '@primer/react-brand'
import {ContentfulContentBlock} from './ContentfulContentBlock'
import type {ContentSchema} from './lib/types/contentful/content-schema'
import type {EntrySchema} from './lib/types/contentful/entry-schema'
import {FindLabelText} from './helpers/find-label-text'

export interface CustomSignupContentProps {
  contentfulContent: {
    entry: EntrySchema
    content_entries: ContentSchema[]
    assets: string[]
  }
}

export function CustomSignupContent({contentfulContent}: CustomSignupContentProps) {
  const title = contentfulContent.entry.fields.heading
  const text = contentfulContent.entry.fields.text
  const labelText = FindLabelText(contentfulContent.content_entries)

  return (
    <ThemeProvider colorMode={'dark'} style={{backgroundColor: 'transparent'}}>
      {labelText ? (
        <Label color="purple" size="small" className="mb-2">
          {labelText}
        </Label>
      ) : null}
      <Heading as="h2" size="6" weight="semibold" className="mb-4">
        {title}
      </Heading>
      {/* TODO: In https://github.com/github/new-user-experience/issues/805, replace with dynamic bullet style */}
      <ContentfulContentBlock text={text} bulletStyle={'default'} />
    </ThemeProvider>
  )
}
