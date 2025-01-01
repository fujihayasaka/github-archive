import type {CopilotFreeUserChecklistProps} from '../CopilotFreeUserChecklist'

export function getCopilotFreeUserChecklistProps(): CopilotFreeUserChecklistProps {
  return {
    dismissed: false,
    checklistState: [true, false, false],
    timeKey: 123456789,
  }
}
