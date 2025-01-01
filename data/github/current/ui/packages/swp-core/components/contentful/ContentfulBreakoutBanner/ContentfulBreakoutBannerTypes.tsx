import type {PrimerComponentBreakoutBanner} from '../../../schemas/contentful/contentTypes/primerComponentBreakoutBanner'

import type {BreakoutBannerProps, HeadingProps, StackProps} from '@primer/react-brand'

type SubComponentProps = {
  headingProps?: Pick<HeadingProps, 'as' | 'size'>
  linkGroupProps?: Pick<StackProps, 'direction'>
}

export type ContentfulBreakoutBannerProps = {
  component: PrimerComponentBreakoutBanner
  className?: string
} & SubComponentProps &
  Omit<BreakoutBannerProps, 'children'>
