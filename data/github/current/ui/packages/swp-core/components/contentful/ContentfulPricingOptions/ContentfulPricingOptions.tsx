import {InlineLink, PricingOptions} from '@primer/react-brand'
import {BLOCKS, INLINES, MARKS, type Document} from '@contentful/rich-text-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {
  PrimerComponentPricingOptions,
  PrimerComponentPricingOptionsFeatureListGroupHeading,
  PrimerComponentPricingOptionsFeatureListHeading,
  PrimerComponentPricingOptionsFeatureListItem,
} from '../../../schemas/contentful/contentTypes/primerComponentPricingOptions'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {ContentfulInlineFootnote} from '../ContentfulFootnotes/ContentfulInlineFootnote'

export type ContentfulPricingOptionsProps = {
  component: PrimerComponentPricingOptions
}

// We use rich text for content flexibility, even though current fields only support paragraph text.
// This ensures future compatibility if we decide to enhance the content model.
const documentToPlainText = (document: Document) => {
  return documentToReactComponents(document, {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => children,
    },
  })
}

export function ContentfulPricingOptions({component}: ContentfulPricingOptionsProps) {
  const {align, variant, items} = component.fields
  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')

  return (
    <PricingOptions variant={variant} align={align}>
      {items.map(({sys, fields}, i) => {
        const {
          label,
          heading,
          headingLevel,
          description,
          currencyCode,
          currentPrice,
          currencySymbol,
          originalPrice,
          priceTrailingText,
          accordionHeadingLevel,
          featureList,
          featureListExpanded,
          featureListHasDivider,
          callToActionPrimary,
          callToActionPrimaryVariant,
          callToActionSecondary,
          callToActionSecondaryVariant,
          footnote,
        } = fields

        return (
          <PricingOptions.Item key={sys.id}>
            {label && <PricingOptions.Label>{label.fields.text}</PricingOptions.Label>}
            {heading && (
              <PricingOptions.Heading as={headingLevel}>{documentToPlainText(heading)}</PricingOptions.Heading>
            )}
            {description && <PricingOptions.Description>{documentToPlainText(description)}</PricingOptions.Description>}

            <PricingOptions.Price
              currencyCode={currencyCode}
              currencySymbol={currencySymbol}
              originalPrice={originalPrice}
              trailingText={priceTrailingText}
            >
              {documentToPlainText(currentPrice)}
            </PricingOptions.Price>

            {featureList && featureList.length > 0 && (
              <PricingOptions.FeatureList
                expanded={featureListExpanded}
                hasDivider={featureListHasDivider}
                accordionAs={accordionHeadingLevel}
              >
                {featureList.map(feature => {
                  if (feature.sys.contentType.sys.id === 'primerComponentPricingItemListHeading') {
                    const featureListHeading = feature as PrimerComponentPricingOptionsFeatureListHeading
                    return (
                      <PricingOptions.FeatureListHeading key={feature.sys.id}>
                        {documentToPlainText(featureListHeading.fields.heading)}
                      </PricingOptions.FeatureListHeading>
                    )
                  }

                  if (feature.sys.contentType.sys.id === 'primerComponentPricingOptionsListHeading') {
                    const featureListGroupHeading = feature as PrimerComponentPricingOptionsFeatureListGroupHeading
                    const featureListGroupHeadingLevel = featureListGroupHeading.fields.headingLevel

                    // Only spread the `as` prop if a heading level is defined;
                    // passing `as={undefined}` causes the incorrect heading level to be rendered.
                    // PB Issue: https://github.com/primer/brand/issues/1007
                    const props = {
                      ...(featureListGroupHeadingLevel && {
                        as: featureListGroupHeadingLevel,
                      }),
                    }

                    return (
                      <PricingOptions.FeatureListGroupHeading {...props} key={feature.sys.id}>
                        {documentToPlainText(featureListGroupHeading.fields.heading)}
                      </PricingOptions.FeatureListGroupHeading>
                    )
                  }

                  const featureListItem = feature as PrimerComponentPricingOptionsFeatureListItem
                  return (
                    <PricingOptions.FeatureListItem key={feature.sys.id} variant={featureListItem.fields.variant}>
                      {documentToReactComponents(featureListItem.fields.description, {
                        renderNode: {
                          [BLOCKS.PARAGRAPH]: (_, children) => {
                            return children
                          },
                          [INLINES.EMBEDDED_ENTRY]: node => {
                            if (footnotesEnabled && node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
                              return (
                                <ContentfulInlineFootnote
                                  component={node.data.target}
                                  analyticsLocation={`pricing_options_${i + 1}`}
                                />
                              )
                            }

                            return null
                          },
                        },
                        renderMark: {
                          [MARKS.BOLD]: text => <strong>{text}</strong>,
                        },
                      })}
                    </PricingOptions.FeatureListItem>
                  )
                })}
              </PricingOptions.FeatureList>
            )}
            {callToActionPrimary && (
              <PricingOptions.PrimaryAction
                as="a"
                href={callToActionPrimary.fields.href}
                hasArrow={false}
                variant={callToActionPrimaryVariant ?? 'accent'}
                {...getAnalyticsEvent(
                  {
                    action: callToActionPrimary.fields.text,
                    tag: 'button',
                    context: 'CTAs',
                    location: `pricing_options_${i + 1}`,
                  },
                  {context: false},
                )}
              >
                {callToActionPrimary.fields.text}
              </PricingOptions.PrimaryAction>
            )}
            {callToActionSecondary && (
              <PricingOptions.SecondaryAction
                as="a"
                href={callToActionSecondary.fields.href}
                hasArrow={false}
                variant={callToActionSecondaryVariant ?? 'subtle'}
                {...getAnalyticsEvent(
                  {
                    action: callToActionSecondary.fields.text,
                    tag: 'button',
                    context: 'CTAs',
                    location: `pricing_options_${i + 1}`,
                  },
                  {context: false},
                )}
              >
                {callToActionSecondary.fields.text}
              </PricingOptions.SecondaryAction>
            )}

            {footnote && (
              <PricingOptions.Footnote>
                {documentToReactComponents(footnote, {
                  renderNode: {
                    [BLOCKS.PARAGRAPH]: (_, children) => children,
                    [INLINES.EMBEDDED_ENTRY]: node => {
                      if (node.data.target.sys.contentType.sys.id === 'link') {
                        const {text, href, openInNewTab} = node.data.target.fields
                        return (
                          <InlineLink
                            href={href}
                            target={openInNewTab ? '_blank' : undefined}
                            {...getAnalyticsEvent({
                              action: text,
                              tag: 'hyperlink',
                              context: 'footnotes',
                              location: `pricing_options_${i + 1}`,
                            })}
                          >
                            {text}
                          </InlineLink>
                        )
                      }
                    },
                  },
                })}
              </PricingOptions.Footnote>
            )}
          </PricingOptions.Item>
        )
      })}
    </PricingOptions>
  )
}
