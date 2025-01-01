import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'

import {Box, Stack, Text, Button} from '@primer/react-brand'

import {getAnalyticsEvent, toSnakeCase} from '@github-ui/swp-core/lib/utils/analytics'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import type {GenericContent} from '../../../../../brand/lib/types/contentful'

import {PLAN_TYPES, type PlanType} from '../../_context/PlanTypeContext'

function renderRichText(richText: RichText) {
  return documentToReactComponents(richText, {
    renderMark: {
      [MARKS.BOLD]: text => (
        <Text as="span" variant="default" weight="semibold" className="is-sansSerifAlt">
          {text}
        </Text>
      ),
    },
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => (
        <Text as="span" variant="muted">
          {children}
        </Text>
      ),
    },
  })
}

type Props = {
  contentfulContent: GenericContent
  planType: PlanType
}

const plans = {
  [PLAN_TYPES.Individual]: ['Free', 'Pro', 'ProPlus'],
  [PLAN_TYPES.Business]: ['Business', 'Enterprise'],
}

export function CompareTableHeader(props: Props) {
  const {contentfulContent, planType} = props
  const {heading, content} = contentfulContent.fields

  const filteredTableColumns = content?.filter(column => plans[planType].includes(column.fields.id)) as GenericContent[]

  return (
    <Stack
      direction="horizontal"
      gap={32}
      padding="none"
      className="border-bottom pb-4 mb-4 mb-md-0 lp-Pricing-table-header lp-Pricing-table-header-noAnchorNav z-3 top-0"
    >
      <Box className="flex-1 col-12 col-md-3">
        <Text size="500">{heading}</Text>
      </Box>

      <Stack role="rowgroup" direction="vertical" gap={4} padding="none" className="col-1 col-md-8 d-none d-md-flex">
        <Stack role="row" direction="horizontal" gap={32} padding="none">
          <div role="columnheader" className="position-absolute">
            <span className="sr-only">Pricing plans</span>
          </div>

          {filteredTableColumns &&
            filteredTableColumns.map(column => {
              const columnLink = column.fields.links?.at(0)

              return (
                <div key={column.sys.id} role="columnheader" className="col-4 px-4 px-md-0 flex-1">
                  {column.fields.heading ? (
                    <Text as="p" size="300" weight="semibold">
                      {column.fields.heading}
                    </Text>
                  ) : null}

                  {column.fields.subheading ? (
                    <Text as="p" size="100" weight="normal" className="mb-3">
                      {renderRichText(column.fields.subheading)}
                    </Text>
                  ) : null}

                  {columnLink ? (
                    <Button
                      as="a"
                      href={columnLink.fields.href}
                      variant="primary"
                      hasArrow={false}
                      size="small"
                      {...getAnalyticsEvent({
                        action: toSnakeCase(columnLink.fields.text),
                        tag: 'button',
                        context: `${toSnakeCase(column.fields.id || '')}_plan`,
                        location: 'comparison_table',
                      })}
                    >
                      {columnLink.fields.text}
                    </Button>
                  ) : null}
                </div>
              )
            })}
        </Stack>
      </Stack>
    </Stack>
  )
}
