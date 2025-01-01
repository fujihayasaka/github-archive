import {CheckCircleIcon, XCircleIcon} from '@primer/octicons-react'

interface ImageDefinitionGenericStatusIndicatorProps {
  value: boolean
}

export function ImageDefinitionGenericStatusIndicator({value}: ImageDefinitionGenericStatusIndicatorProps) {
  return value ? (
    <CheckCircleIcon className="fgColor-success" size={16} />
  ) : (
    <XCircleIcon className="fgColor-danger" size={16} />
  )
}
