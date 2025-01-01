import {userHovercardPath} from '@github-ui/paths'
import {Link} from '@primer/react'

import suggesterName from '../utilities/suggester-name'
import {type DisplayTaskData, TaskTypes} from '../utilities/workspace-editor-types'

const SUPPORTED_TASK_LOCATION_TYPES = [TaskTypes.Suggestion, TaskTypes.Generative]

interface SuggestionTitleProps {
  task?: DisplayTaskData
  useHovercard?: boolean
}

export function SuggestionTitle({task, useHovercard}: SuggestionTitleProps) {
  if (!task) return <>Thread</>

  const displayHandle = suggesterName(task.author)
  const locationString = locationInfo(task)
  let authorDetail = <>@{displayHandle}</>
  if (useHovercard) {
    authorDetail = (
      <Link
        className="color-fg-default"
        data-hovercard-url={userHovercardPath({owner: displayHandle})}
        href={displayHandle}
      >
        @{displayHandle}
      </Link>
    )
  }
  let title
  switch (task.type) {
    case 'autofix':
    case 'suggestion':
      title = <>Suggestion from {authorDetail}</>
      break
    case 'generative':
      title = <>Thread by {authorDetail}</>
      break
    default:
      title = <>Thread</>
      break
  }

  return (
    <>
      {title} {locationString}
    </>
  )
}

function locationInfo(task: DisplayTaskData): string | undefined {
  if (!SUPPORTED_TASK_LOCATION_TYPES.includes(task.type)) return

  const fileName = `on ${task.path.split('/').pop() || ''}`
  if (task.lineNumber) {
    if (task.startLineNumber && task.startLineNumber !== task.lineNumber) {
      return `${fileName}:${task.startLineNumber}-${task.lineNumber}`
    } else {
      return `${fileName}:${task.lineNumber}`
    }
  }

  return fileName
}
