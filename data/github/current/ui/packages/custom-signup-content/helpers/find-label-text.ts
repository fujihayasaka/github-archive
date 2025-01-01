import type {ContentSchema} from '../lib/types/contentful/content-schema'

// By default, we will not include a label.
// If a content author has added a label in Contentful, we'll display that label's text.
export const FindLabelText = (contentEntries: ContentSchema[]): string | null => {
  const findEntry = contentEntries.find(entry => entry.fields.htmlId === 'signup-pill')
  return findEntry ? findEntry.fields?.heading : null
}
