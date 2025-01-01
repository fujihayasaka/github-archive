import {Label} from '@primer/react-brand'
import type {PrimerComponentLabel} from '../../../schemas/contentful/contentTypes/primerComponentLabel'
import {getPrimerIcon} from '../../../lib/utils/icons'

export type ContentfulLabelProps = {
  component: PrimerComponentLabel
}

export const ContentfulLabel = ({component}: ContentfulLabelProps) => {
  const {text, size, color, icon} = component.fields
  const Octicon = getPrimerIcon(icon)

  return (
    <Label size={size} color={color} {...(Octicon ? {leadingVisual: <Octicon />} : {})}>
      {text}
    </Label>
  )
}
