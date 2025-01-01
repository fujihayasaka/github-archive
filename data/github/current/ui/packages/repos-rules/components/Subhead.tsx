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

type SubheadLabelProps = {
  alphaOrBeta?: string
}

const SubheadLabel: FC<SubheadLabelProps> = ({alphaOrBeta}) => {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  if (!alphaOrBeta) {
    return null
  }
  if (lifecycleLabelNameEnabled) {
    if (alphaOrBeta === 'beta') {
      return <BetaLabel className="mr-2" />
    }
    if (alphaOrBeta === 'alpha') {
      return <AlphaLabel className="mr-2" />
    }
  }
  return (
    <Label variant="success" sx={{mr: 2}}>
      {alphaOrBeta === 'beta' ? 'Beta' : 'Alpha'}
    </Label>
  )
}

export const Subhead: FC<SubheadProps> = ({heading, description, className, alphaOrBeta, renderAction}) => {
  const enterpriseNavRedesignEnabled = true
  const labelVisible = !enterpriseNavRedesignEnabled
  return (
    <div className={`Subhead d-flex flex-justify-between flex-items-center ${className || ''}`}>
      <div className={'d-flex flex-items-center gap-2'}>
        <h1 className="Subhead-heading f2-light h1-override-shared-component">{heading}</h1>
        {labelVisible && <SubheadLabel alphaOrBeta={alphaOrBeta} />}
        {description ? <p className="Subhead-description mb-2">{description}</p> : null}
      </div>

      {renderAction && renderAction()}
    </div>
  )
}
