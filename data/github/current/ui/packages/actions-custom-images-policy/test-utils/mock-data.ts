import type {ActionsCustomImagesPolicyProps} from '../ActionsCustomImagesPolicy'

export function getActionsCustomImagesPolicyProps(): ActionsCustomImagesPolicyProps {
  return {
    accessPolicy: 'none',
    action: 'path/to/custom-images-policy',
  }
}
