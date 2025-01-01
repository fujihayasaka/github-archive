import ModelInfo from './ModelInfo'
import ModelParameters from './ModelParameters'
import type {ModelState} from '../../../types'
import {SidebarSelectionOptions} from '../../../types'

interface SidebarContentProps {
  activeTab: SidebarSelectionOptions
  modelState: ModelState
  position: number
  headingLevel?: 'h2' | 'h3'
}

export function SidebarContent({activeTab, headingLevel = 'h3', modelState, position}: SidebarContentProps) {
  switch (activeTab) {
    case SidebarSelectionOptions.DETAILS:
      return <ModelInfo headingLevel={headingLevel} model={modelState.catalogData} />
    case SidebarSelectionOptions.PARAMETERS:
    default:
      return <ModelParameters model={modelState} position={position} />
  }
}
