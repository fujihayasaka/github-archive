import {NavList} from '@primer/react'
import {getStepStatusIcon} from './StatusIcon'

export function SessionPane() {
  return (
    <NavList>
      <NavList.Item>
        <NavList.LeadingVisual>{getStepStatusIcon('in-progress')}</NavList.LeadingVisual>
        Step 1
      </NavList.Item>
      <NavList.Item>
        <NavList.LeadingVisual>{getStepStatusIcon('success')}</NavList.LeadingVisual>
        Step 2
      </NavList.Item>
      <NavList.Item>
        <NavList.LeadingVisual>{getStepStatusIcon('blocked')}</NavList.LeadingVisual>
        Step 3
      </NavList.Item>
      <NavList.Item>
        <NavList.LeadingVisual>{getStepStatusIcon('error')}</NavList.LeadingVisual>
        Step 4
      </NavList.Item>
    </NavList>
  )
}
