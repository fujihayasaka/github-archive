import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'

import {Heading, InlineLink, Label, Link, River, Text} from '@primer/react-brand'

import {getAnalyticsEvent, documentToPlainTextString} from '@github-ui/swp-core/lib/utils/analytics'

import {Image} from '../../../../../components/Image/Image'
import type {GenericContent} from '../../../../../brand/lib/types/contentful'

type Props = {
  river: GenericContent
}

export function FeaturesRiver(props: Props) {
  const {river} = props

  const {media, text, heading, label, links} = river.fields
  const firstImage = media?.at(0)
  const firstLink = links?.at(0)

  return (
    <River imageTextRatio="50:50" className="lp-River-mod">
      {firstImage ? (
        <River.Visual className="lp-River-visual">
          <Image
            src={firstImage.fields.asset.fields.file.url}
            alt={firstImage.fields.description || ''}
            width="708"
            height="472"
          />
        </River.Visual>
      ) : (
        <> </>
      )}

      <River.Content>
        {label ? <Label color="green-blue">{label.fields.text}</Label> : <></>}

        <Heading as="h3" size="5">
          {heading}
        </Heading>

        {text ? (
          <Text as="p" variant="muted" className="lp-River-text">
            {documentToReactComponents(text, {
              renderNode: {
                [BLOCKS.PARAGRAPH]: (_, children) => (
                  <Text as="span" variant="muted">
                    {children}
                  </Text>
                ),
                [INLINES.HYPERLINK]: (node, children) => (
                  <InlineLink
                    href={node.data.uri}
                    {...getAnalyticsEvent({
                      action: documentToPlainTextString(node, ' '),
                      tag: 'link',
                      context: heading,
                      location: 'features_rivers',
                    })}
                  >
                    {children}
                  </InlineLink>
                ),
              },
            })}
          </Text>
        ) : (
          <></>
        )}

        {firstLink ? (
          <Link
            href={firstLink.fields.href}
            variant="accent"
            {...getAnalyticsEvent({
              action: firstLink.fields.text,
              tag: 'link',
              context: heading,
              location: 'features_rivers',
            })}
          >
            {firstLink.fields.text}
          </Link>
        ) : (
          <></>
        )}
      </River.Content>
    </River>
  )
}
