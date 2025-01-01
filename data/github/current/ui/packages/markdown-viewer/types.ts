import type {TaskItem} from '@github-ui/use-tasklist'

export type OnConvertToIssueCallback = (
  task: TaskItem,
  setIsConverting: (converting: boolean) => void,
  onCompletedCallback?: () => void,
  onErrorCallback?: (error: Error) => void,
) => void

export type OnConvertToSubIssueCallback = (
  task: TaskItem,
  setIsConverting: (converting: boolean) => void,
  onCompletedCallback?: () => void,
  onErrorCallback?: (error: Error) => void,
) => void
