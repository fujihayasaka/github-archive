import {ArrowLeftIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'

import {useSuggestionContext} from '../contexts/SuggestionContext'
import {useSuggestions} from '../hooks/use-suggestions'
import {TaskTypes} from '../utilities/workspace-editor-types'
import {RightSidePanelHeader} from './RightSidePanelComponents'
import {SuggestionTitle} from './SuggestionTitle'

export function SuggestionPanelHeader() {
  const {clearFocusedTaskId, focusedTask: currentTask} = useSuggestionContext()
  const {refetchSuggestions} = useSuggestions()

  const goBack = () => {
    clearFocusedTaskId()
    refetchSuggestions()
  }

  if (currentTask) {
    switch (currentTask.type) {
      case TaskTypes.Autofix:
      case TaskTypes.Suggestion:
      case TaskTypes.Generative:
        return (
          <RightSidePanelHeader
            leftContent={
              <IconButton
                aria-label="View all suggestions"
                icon={ArrowLeftIcon}
                variant="invisible"
                size="medium"
                onClick={goBack}
              />
            }
            title={<SuggestionTitle useHovercard task={currentTask} />}
          />
        )
      default:
        return <RightSidePanelHeader title="Suggestion" />
    }
  } else {
    return <RightSidePanelHeader title="Suggestions" />
  }
}
