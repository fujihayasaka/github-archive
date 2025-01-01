import type {AnimateProps, GridColumnIndex, ImageAspectRatio} from '@primer/react-brand'

export type CategoryCard = {
  href: string
  heading: string
  publishedDate?: string
  ctaText: string
  className?: string
}

export type CategoryCardsProps = {
  className?: string
  hasBorder?: boolean
  spanOpts?: {[key: string]: GridColumnIndex}
  fullWidth?: boolean
  animate?: AnimateProps
  imageAspectRatio?: ImageAspectRatio
  cards: CategoryCard[]
}
