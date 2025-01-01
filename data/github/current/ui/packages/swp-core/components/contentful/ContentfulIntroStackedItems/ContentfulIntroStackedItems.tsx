import {Box, Grid, Heading, Link, Stack, Text} from '@primer/react-brand'
import {BLOCKS, MARKS, type Document} from '@contentful/rich-text-types'
import {documentToReactComponents, type Options} from '@contentful/rich-text-react-renderer'
import type {IntroStackedItems} from '../../../schemas/contentful/contentTypes/introStackedItems'
import styles from './ContentfulIntroStackedItems.module.css'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'

type StackedItemProps = {
  content: Document
}

const StackedItem = ({content}: StackedItemProps) => {
  const option: Options = {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => {
        return children
      },
    },
    renderMark: {
      [MARKS.BOLD]: children => <Text variant="default">{children}</Text>,
    },
  }
  return <>{documentToReactComponents(content, option)}</>
}

type ContentfulIntroStackedItemsProps = {
  component: IntroStackedItems
  className?: string
}

export function ContentfulIntroStackedItems({component, className}: ContentfulIntroStackedItemsProps) {
  const {headline, items, link} = component.fields

  return (
    <Box className={className} marginBlockEnd={40}>
      <Grid>
        <Grid.Column span={{medium: 5}}>
          <Box className={styles.sectionIntro}>
            <Box marginBlockEnd={24}>
              <Heading as="h2" size="3">
                {headline}
              </Heading>
            </Box>
            {link && (
              <Link
                href={link.fields.href}
                {...getAnalyticsEvent({
                  action: link.fields.text,
                  tag: 'link',
                  context: 'CTAs',
                  location: headline,
                })}
              >
                {link.fields.text}
              </Link>
            )}
          </Box>
        </Grid.Column>
        <Grid.Column span={{medium: 6}} start={{medium: 7}}>
          <Stack direction="vertical" padding="none" gap={24}>
            {items.map(item => (
              <Text key={item.sys.id} as="p" variant="muted">
                <StackedItem content={item.fields.text} />
              </Text>
            ))}
          </Stack>
        </Grid.Column>
      </Grid>
    </Box>
  )
}
