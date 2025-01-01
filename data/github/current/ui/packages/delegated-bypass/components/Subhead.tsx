import type {FC} from 'react'
import {Heading, Label} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type SubheadProps = {
  heading: string
  description?: string
  className?: string
  beta?: boolean
  renderAction?: () => JSX.Element | null
}

export const Subhead: FC<SubheadProps> = ({heading, description, className, beta, renderAction}) => {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const enterpriseNavRedesignEnabled = true
  return (
    <div className={`d-flex flex-justify-between flex-items-center Subhead ${className || ''}`}>
      <div className="d-flex flex-items-center gap-2">
        <Heading as="h1" className="Subhead-heading f2 text-light h1-override-shared-component">
          {heading}
        </Heading>
        {beta && !enterpriseNavRedesignEnabled ? (
          lifecycleLabelNameEnabled ? (
            <div className="ml-2">
              <BetaLabel />
            </div>
          ) : (
            <Label className="ml-2" variant="success">
              Beta
            </Label>
          )
        ) : null}
        {description ? <span className="Subhead-description mb-2">{description}</span> : null}
      </div>

      {renderAction?.()}
    </div>
  )
}
