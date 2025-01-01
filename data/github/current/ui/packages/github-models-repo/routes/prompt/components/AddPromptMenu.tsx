import {PlusIcon, RepoForkedIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {sendEvent, type SendEventContext} from '../../../utils/send-event'
import {CompareForkPromptClicked, CompareNewPromptClicked} from '../types'

interface AddPromptMenuProps {
  onFork: () => void
  onAdd: () => void
  totalPrompts: number
}

const maxPromptsLimit = 20

export function AddPromptMenu({onAdd, onFork, totalPrompts}: AddPromptMenuProps) {
  const canAddPrompt = totalPrompts < maxPromptsLimit

  return (
    <ActionMenu>
      <ActionMenu.Button leadingVisual={PlusIcon} size="small">
        Add prompt
      </ActionMenu.Button>
      <ActionMenu.Overlay>
        <ActionList>
          <ActionList.Item
            onSelect={() => {
              onFork()
              const payload: SendEventContext = {totalPrompts}
              sendEvent(CompareForkPromptClicked, payload)
            }}
          >
            <ActionList.LeadingVisual>
              <RepoForkedIcon />
            </ActionList.LeadingVisual>
            Copy original prompt
          </ActionList.Item>
          <ActionList.Item
            onSelect={() => {
              onAdd()
              const payload: SendEventContext = {totalPrompts}
              sendEvent(CompareNewPromptClicked, payload)
            }}
            disabled={!canAddPrompt}
          >
            <ActionList.LeadingVisual>
              <PlusIcon />
            </ActionList.LeadingVisual>
            New prompt
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
