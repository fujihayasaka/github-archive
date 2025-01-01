import {Box, Grid, Heading, Link, Stack, Text} from '@primer/react-brand'
import {BLOCKS, MARKS, type Document} from '@contentful/rich-text-types'
import {documentToReactComponents, type Options} from '@contentful/rich-text-react-renderer'
import {clsx} from 'clsx'

import type {IntroStackedItems} from '../../../schemas/contentful/contentTypes/introStackedItems'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import styles from './ContentfulIntroStackedItems.module.css'

type ContentfulIntroStackedItemsProps = {
  component: IntroStackedItems
  className?: string
}

export function ContentfulIntroStackedItems({component, className}: ContentfulIntroStackedItemsProps) {
  const {headline, items, link} = component.fields

  return (
    <Box className={clsx(styles.wrapper, className)} marginBlockEnd={40}>
      <Grid>
        <Grid.Column span={{large: 5}}>
          <Box className={styles.sectionIntro}>
            <IntroHeading headline={headline} />
            {link && (
              <Link
                href={link.fields.href}
                variant="accent"
                size="large"
                {...getAnalyticsEvent({
                  action: link.fields.text,
                  tag: 'link',
                  context: 'CTAs',
                  location: typeof headline === 'string' ? headline : documentToPlainTextString(headline),
                })}
              >
                {link.fields.text}
              </Link>
            )}
          </Box>
        </Grid.Column>
        <Grid.Column span={{large: 6}} start={{large: 7}}>
          <Stack direction="vertical" padding="none" className={styles.stackedItems}>
            {items.map(item => (
              <StackedItem key={item.sys.id} content={item.fields.text} />
            ))}
          </Stack>
        </Grid.Column>
      </Grid>
    </Box>
  )
}

type IntroHeadingProps = {
  headline: string | Document
}

const IntroHeading = ({headline}: IntroHeadingProps) => {
  return (
    <Heading className={styles.heading} as="h2">
      {typeof headline === 'string'
        ? headline
        : documentToReactComponents(headline, {
            renderMark: {
              [MARKS.BOLD]: text => (
                <Text className={styles.headingText} weight="semibold" variant="default">
                  {text}
                </Text>
              ),
            },
            renderNode: {
              [BLOCKS.PARAGRAPH]: (_, children) => (
                <Text className={styles.headingText} weight="semibold" variant="muted">
                  {children}
                </Text>
              ),
            },
          })}
    </Heading>
  )
}

type StackedItemProps = {
  content: Document
}

const StackedItem = ({content}: StackedItemProps) => {
  const option: Options = {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => {
        return (
          <Text className={styles.stackedItemText} weight="medium" variant="muted">
            {children}
          </Text>
        )
      },
    },
    renderMark: {
      [MARKS.BOLD]: children => (
        <Text className={styles.stackedItemText} weight="semibold" variant="default">
          {children}
        </Text>
      ),
    },
  }
  return <Text as="p">{documentToReactComponents(content, option)}</Text>
}
