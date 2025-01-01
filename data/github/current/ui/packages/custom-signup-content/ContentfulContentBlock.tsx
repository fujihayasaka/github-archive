import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS} from '@contentful/rich-text-types'
import {Text, UnorderedList} from '@primer/react-brand'
import type {RichContentSchema} from './lib/types/contentful/rich-content-schema'

const BulletStyle = {
  default: 'default',
  checked: 'checked',
} as const

type BulletStyle = (typeof BulletStyle)[keyof typeof BulletStyle]

type ContentfulContentBlockProps = {
  text: RichContentSchema['fields']['text']
  bulletStyle: BulletStyle
}

export const ContentfulContentBlock = ({text, bulletStyle}: ContentfulContentBlockProps): React.ReactNode => {
  return documentToReactComponents(text, {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => (
        <Text as="p" size="100" className="mb-4">
          {children}
        </Text>
      ),
      [BLOCKS.UL_LIST]: (_, children) => <UnorderedList variant={bulletStyle}>{children}</UnorderedList>,
      [BLOCKS.LIST_ITEM]: (_, children) => {
        return (
          <UnorderedList.Item>
            <Text size="100">{children}</Text>
          </UnorderedList.Item>
        )
      },
    },
  })
}
