import {PricingOptions} from '@primer/react-brand'
import type {
  PrimerComponentPricingOptions,
  PrimerComponentPricingOptionsFeatureListHeading,
  PrimerComponentPricingOptionsFeatureListItem,
} from '../../../schemas/contentful/contentTypes/primerComponentPricingOptions'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, type Document} from '@contentful/rich-text-types'

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
  const {variant, items} = component.fields

  return (
    <PricingOptions variant={variant}>
      {items.map(({sys, fields}, i) => {
        const {
          label,
          heading,
          description,
          currencyCode,
          currentPrice,
          currencySymbol,
          originalPrice,
          priceTrailingText,
          featureList,
          featureListExpanded,
          featureListHasDivider,
          callToActionPrimary,
          callToActionSecondary,
          footnote,
        } = fields

        return (
          <PricingOptions.Item key={sys.id}>
            {label && <PricingOptions.Label>{label.fields.text}</PricingOptions.Label>}
            {heading && <PricingOptions.Heading>{documentToPlainText(heading)}</PricingOptions.Heading>}
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
              <PricingOptions.FeatureList expanded={featureListExpanded} hasDivider={featureListHasDivider}>
                {featureList.map(feature => {
                  if (feature.sys.contentType.sys.id === 'primerComponentPricingOptionsListHeading') {
                    const featureListHeading = feature as PrimerComponentPricingOptionsFeatureListHeading
                    return (
                      <PricingOptions.FeatureListHeading key={feature.sys.id}>
                        {documentToPlainText(featureListHeading.fields.heading)}
                      </PricingOptions.FeatureListHeading>
                    )
                  }

                  const featureListItem = feature as PrimerComponentPricingOptionsFeatureListItem
                  return (
                    <PricingOptions.FeatureListItem key={feature.sys.id} variant={featureListItem.fields.variant}>
                      {documentToPlainText(featureListItem.fields.description)}
                    </PricingOptions.FeatureListItem>
                  )
                })}
              </PricingOptions.FeatureList>
            )}
            {callToActionPrimary && (
              <PricingOptions.PrimaryAction
                as="a"
                href={callToActionPrimary.fields.href}
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

            {footnote && <PricingOptions.Footnote>{documentToPlainText(footnote)}</PricingOptions.Footnote>}
          </PricingOptions.Item>
        )
      })}
    </PricingOptions>
  )
}
