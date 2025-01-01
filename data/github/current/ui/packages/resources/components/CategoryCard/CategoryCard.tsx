import type {LabelColors} from '@primer/react-brand'
import {Box, Card} from '@primer/react-brand'
import {BLOCKS, type Document} from '@contentful/rich-text-types'
import {documentToReactComponents, type Options} from '@contentful/rich-text-react-renderer'
import styles from './CategoryCard.module.css'

type CategoryCardProps = {
  path: string
  imageUrl?: string
  imageDescription?: string
  title: string
  label?: string
  labelColor?: (typeof LabelColors)[number]
  excerpt: Document
  analyticsEvent: object
  dataRef?: string
}

type ExcerptProps = {
  content: Document
}

const Excerpt = ({content}: ExcerptProps) => {
  const option: Options = {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => {
        return children
      },
    },
  }

  return <>{documentToReactComponents(content, option)}</>
}

export function CategoryCard({
  path,
  imageUrl,
  imageDescription,
  title,
  label,
  labelColor,
  excerpt,
  analyticsEvent,
  dataRef,
}: CategoryCardProps) {
  return (
    <Box animate="fade-in">
      <Card
        {...analyticsEvent}
        data-ref={dataRef}
        href={path}
        variant="minimal"
        className={styles.categoryCard}
        fullWidth
      >
        <Card.Image
          src={
            imageUrl ? `${imageUrl}?w=1000&fm=jpg&fl=progressive` : '/images/modules/site/contentful/default/md.webp'
          }
          alt={imageDescription || ''}
          className={styles.categoryCardImage}
        />
        <Card.Heading>{title}</Card.Heading>
        {label && <Card.Label color={labelColor || 'default'}>{label}</Card.Label>}
        <Card.Description>
          <Excerpt content={excerpt} />
        </Card.Description>
      </Card>
    </Box>
  )
}
