import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import type {Block as BlockType, Text as TextType} from '@contentful/rich-text-types'

import {Box, Text, UnorderedList} from '@primer/react-brand'
import {CheckIcon, DashIcon, SyncIcon, InfinityIcon} from '@primer/octicons-react'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import type {CopilotFeatureStatus} from '../../../../../brand/lib/types/contentful'

function renderRichText(richText: RichText) {
  return documentToReactComponents(richText, {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => <Text size="100">{children}</Text>,
      [BLOCKS.UL_LIST]: (_, children) => <UnorderedList variant="checked">{children}</UnorderedList>,
      [BLOCKS.LIST_ITEM]: node => {
        const nodeContent = node.content.at(0) as BlockType
        const textContent = nodeContent.content.at(0) as TextType
        const isMuted = textContent.marks.some(mark => mark.type === MARKS.STRIKETHROUGH)

        if (isMuted) {
          return (
            <UnorderedList.Item
              leadingVisual={DashIcon}
              leadingVisualAriaLabel="Not included icon"
              className="fgColor-muted"
              variant="muted"
            >
              <Text size="100" variant="muted">
                {textContent.value}
              </Text>
            </UnorderedList.Item>
          )
        } else {
          return (
            <UnorderedList.Item leadingVisualFill="var(--brand-color-success-fg)">
              <Text size="100">{textContent.value}</Text>
            </UnorderedList.Item>
          )
        }
      },
    },
  })
}

type Props = {
  name: string
  status: CopilotFeatureStatus
  text?: RichText
}

export function CompareTableCell(props: Props) {
  const {name, status, text} = props

  const renderSwitch = () => {
    switch (status) {
      case 'Disabled':
        return (
          <>
            <DashIcon size={24} className="fgColor-muted" />
            <span className="sr-only">Not included</span>
          </>
        )
      case 'Enabled':
        return (
          <>
            {text ? (
              renderRichText(text)
            ) : (
              <>
                <CheckIcon size={24} className="fgColor-success" />
                <span className="sr-only">Included</span>
              </>
            )}
          </>
        )
      case 'Refresh':
        return (
          <>
            <SyncIcon size={24} className="fgColor-done ml-2 ml-md-0 mb-md-2 flex-order-2 flex-md-order-1" />

            <div className="flex-order-1 flex-md-order-2">
              {text ? renderRichText(text) : <Text size="100">Refresh</Text>}
            </div>
          </>
        )
      case 'Unlimited':
        return (
          <>
            <InfinityIcon size={24} className="fgColor-success ml-2 ml-md-0 mb-md-2 flex-order-2 flex-md-order-1" />

            <div className="flex-order-1 flex-md-order-2">
              {text ? renderRichText(text) : <Text size="100">Unlimited</Text>}
            </div>
          </>
        )
      default:
        return null
    }
  }

  return (
    <Box role="cell" className="col-12 col-lg-4 lp-CompareTable-cell d-flex flex-row flex-wrap flex-1">
      <Text size="100" weight="semibold" variant="muted" className="d-md-none mr-auto">
        {name} <span className="sr-only">plan</span>
      </Text>

      <div className="d-flex flex-row flex-md-column">{renderSwitch()}</div>
    </Box>
  )
}
