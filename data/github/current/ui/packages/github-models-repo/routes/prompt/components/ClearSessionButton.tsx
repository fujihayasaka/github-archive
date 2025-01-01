import {TrashIcon} from '@primer/octicons-react'
import {Button, Tooltip, useConfirm} from '@primer/react'
import {usePromptCompareManager} from '../prompt-compare-manager'

export function ClearSessionButton({disabled}: {disabled?: boolean}) {
  const manager = usePromptCompareManager()

  const confirm = useConfirm()

  async function handleClick() {
    const confirmed = await confirm({
      title: 'Clear current session?',
      content:
        'This will remove all evaluation inputs and results from the current session. This action cannot be undone.',
      confirmButtonType: 'danger',
      confirmButtonContent: 'Clear',
    })

    if (confirmed) {
      manager.evalsClear()
    }
  }

  if (disabled) {
    return (
      <Tooltip text="Session already cleared">
        <Button size="small" variant="default" inactive>
          Clear session
        </Button>
      </Tooltip>
    )
  }

  return (
    <Button leadingVisual={TrashIcon} size="small" onClick={handleClick}>
      Clear session
    </Button>
  )
}
