import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'
import {Box, Label, Stack, Text, InlineLink} from '@primer/react-brand'

import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'
import {ContentfulInlineFootnote} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnote'

import {getAnalyticsEvent, documentToPlainTextString} from '@github-ui/swp-core/lib/utils/analytics'

import type {CopilotFeature} from '../../../../../brand/lib/types/contentful'

import {CompareTableCell} from './CompareTableCell'

import styles from './styles.module.css'

type Props = {
  contentfulContent: CopilotFeature
  showFree: boolean
  showPro: boolean
  showProPlus: boolean
  showBusiness: boolean
  showEnterprise: boolean
}

export function CompareTableRow(props: Props) {
  const {contentfulContent, showFree, showPro, showProPlus, showBusiness, showEnterprise} = props
  const {sys, fields} = contentfulContent
  const {
    label,
    heading,
    subheading,
    statusForFree,
    statusForPro,
    statusForProPlus,
    statusForBusiness,
    statusForEnterprise,
    customTextForFree,
    customTextForPro,
    customTextForProPlus,
    customTextForBusiness,
    customTextForEnterprise,
  } = fields

  const cells = [
    {name: 'Free', show: showFree, status: statusForFree, text: customTextForFree},
    {name: 'Pro', show: showPro, status: statusForPro, text: customTextForPro},
    {name: 'Pro+', show: showProPlus, status: statusForProPlus, text: customTextForProPlus},
    {name: 'Business', show: showBusiness, status: statusForBusiness, text: customTextForBusiness},
    {name: 'Enterprise', show: showEnterprise, status: statusForEnterprise, text: customTextForEnterprise},
  ]

  function renderRichText(richText: RichText, fontSize: '100' | '200' = '200') {
    return documentToReactComponents(richText, {
      renderNode: {
        [BLOCKS.PARAGRAPH]: (_, children) => (
          <Text as="p" size={fontSize} weight="normal" className={styles.inheritColor}>
            {children}
          </Text>
        ),
        [INLINES.HYPERLINK]: (node, children) => (
          <InlineLink
            href={node.data.uri}
            {...getAnalyticsEvent({
              action: documentToPlainTextString(node, ' '),
              tag: 'hyperlink',
              context: documentToPlainTextString(heading),
              location: 'comparison_table',
            })}
          >
            {children}
          </InlineLink>
        ),
        [INLINES.EMBEDDED_ENTRY]: node => {
          if (node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
            return (
              <ContentfulInlineFootnote
                component={node.data.target}
                analyticsLocation={documentToPlainTextString(heading)}
              />
            )
          }

          return null
        },
      },
    })
  }

  return (
    <Stack
      key={sys.id}
      direction={{narrow: 'vertical', regular: 'horizontal'}}
      gap={{narrow: 16, regular: 32}}
      padding="none"
      className="border-bottom py-4 py-md-3"
      role="row"
    >
      <Box role="rowheader" className="flex-1 col-12 col-md-3">
        {label && (
          <div className="lp-Pricing-table-label-wrap">
            <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label lp-ConicGradientBorder-label-mini d-inline-block">
              <Label size="medium" color="purple-red" className="lp-ConicGradientBorder-label-inner">
                {label.fields.text}
              </Label>
            </div>
          </div>
        )}

        <div className={styles.TableRowHeading}>{renderRichText(heading)}</div>

        {subheading ? (
          <div className={`${styles.TableRowSubheading} mt-3`}>{renderRichText(subheading, '100')}</div>
        ) : null}
      </Box>

      <Stack
        direction={{narrow: 'vertical', regular: 'horizontal'}}
        gap={{narrow: 16, regular: 32}}
        padding="none"
        className="col-12 col-md-8 flex-items-center"
      >
        {cells.map(cell => {
          if (!cell.show) return null

          return <CompareTableCell key={cell.name} name={cell.name} status={cell.status} text={cell.text} />
        })}
      </Stack>
    </Stack>
  )
}
