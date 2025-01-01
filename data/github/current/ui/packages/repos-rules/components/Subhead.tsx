import type {FC} from 'react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {AlphaLabel} from '@github-ui/lifecycle-labels/alpha'
import {Label} from '@primer/react'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type SubheadProps = {
  heading: string
  description?: string
  className?: string
  alphaOrBeta?: string
  renderAction?: () => JSX.Element | null
}

export const Subhead: FC<SubheadProps> = ({heading, description, className, alphaOrBeta, renderAction}) => {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  return (
    <div className={`Subhead d-flex flex-justify-between flex-items-center ${className || ''}`}>
      <div className={'d-flex flex-items-center gap-2'}>
        <h1 className="Subhead-heading f2-light">{heading}</h1>
        {alphaOrBeta === 'beta' &&
          (lifecycleLabelNameEnabled ? (
            <BetaLabel className="mr-2" />
          ) : (
            <Label variant="success" sx={{mr: 2}}>
              Beta
            </Label>
          ))}
        {alphaOrBeta === 'alpha' &&
          (lifecycleLabelNameEnabled ? (
            <AlphaLabel className="mr-2" />
          ) : (
            <Label variant="success" sx={{mr: 2}}>
              Alpha
            </Label>
          ))}
        {description ? <p className="Subhead-description mb-2">{description}</p> : null}
      </div>

      {renderAction && renderAction()}
    </div>
  )
}
