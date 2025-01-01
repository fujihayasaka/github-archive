import type {ImageVersion} from '../types/types'
import {CheckCircleIcon, XCircleIcon} from '@primer/octicons-react'

interface ImageVersionEnabledStateProps {
  imageVersion: ImageVersion
}

export function ImageVersionEnabledState(props: ImageVersionEnabledStateProps) {
  return props.imageVersion.enabled ? (
    <CheckCircleIcon className="fgColor-success" size={16} />
  ) : (
    <XCircleIcon className="fgColor-danger" size={16} />
  )
}
