import type {PrimerComponentBreakoutBanner} from '../../../schemas/contentful/contentTypes/primerComponentBreakoutBanner'

import type {BreakoutBannerProps} from '@primer/react-brand'

export type ContentfulBreakoutBannerProps = {
  component: PrimerComponentBreakoutBanner
  className?: string
} & Omit<BreakoutBannerProps, 'children'>
