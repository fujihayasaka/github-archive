import {Label} from '@primer/react'

import {FeedbackLink, type OptionalFeedbackLinkProps} from './internal-components/FeedbackLink'
import {LabelWithLink} from './internal-components/LabelWithLink'

export interface AlphaLabelProps extends OptionalFeedbackLinkProps {
  /** Override label content if necessary. */
  children?: React.ReactNode
  className?: string
}

/** Indicates a feature that is only available internally to GitHub staff. */
export const AlphaLabel = ({children = 'Private preview', feedbackUrl, className}: AlphaLabelProps) => (
  <LabelWithLink
    className={className}
    label={<Label variant="secondary">{children}</Label>}
    link={feedbackUrl ? <FeedbackLink feedbackUrl={feedbackUrl} /> : undefined}
  />
)
