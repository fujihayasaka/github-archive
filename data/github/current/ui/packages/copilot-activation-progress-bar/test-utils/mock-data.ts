import type {CopilotActivationProgressBarProps} from './../components/CopilotActivationProgressBar'

export function getCopilotActivationProgressBarProps(): CopilotActivationProgressBarProps {
  return {
    segmentPoints: [0, 25, 50, 75, 100],
    currentSegmentIndex: 0,
    color: 'gradient',
  }
}
