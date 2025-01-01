import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {Button, SelectPanel, type ButtonProps} from '@primer/react'
import {memo, useState} from 'react'
import type {DiffEntryData} from '../shared/use-get-diff-entry-data'
import type {ActionListItemInput} from '@primer/react/deprecated'
import {FeatureFlags} from '@primer/react/experimental'

interface DiffHeaderAskCopilotButton {
  anchorProps: ButtonProps
  diffEntries: DiffEntryData[]
  onSubmit: (references: FileDiffReference[]) => void
}

export const AskCopilotDiffEntriesSelectPanel = memo(function CopilotChatDiffHeaderButton({
  anchorProps,
  diffEntries,
  onSubmit,
}: DiffHeaderAskCopilotButton) {
  const [filter, setFilter] = useState('')
  const [open, setOpen] = useState(false)

  const [selected, setSelected] = useState<ActionListItemInput[]>([])

  const items: ActionListItemInput[] = diffEntries.map(diffEntry => ({
    id: diffEntry.path,
    text: diffEntry.path,
    disabled: !diffEntry.reference,
    inactiveText: !diffEntry.reference ? 'Copilot is not available for this file' : undefined,
  }))

  const filteredItems = items.filter(item => item.text?.toLowerCase().includes(filter.toLowerCase()))

  const submitSelectedReferences = () => {
    const selectedReferences = selected
      .map(i => diffEntries.find(item => item.path === i.id))
      .filter(i => i?.reference !== undefined)
      .map(i => i?.reference as FileDiffReference)
    onSubmit(selectedReferences)
  }

  return (
    <FeatureFlags
      flags={{
        primer_react_select_panel_with_modern_action_list: true,
      }}
    >
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <SelectPanel
        width="medium"
        renderAnchor={({children, ...props}) => (
          <Button {...props} {...anchorProps} aria-haspopup="dialog">
            Ask Copilot
          </Button>
        )}
        title="Select files to discuss"
        placeholder="Ask Copilot"
        open={open}
        onOpenChange={setOpen}
        items={filteredItems}
        selected={selected}
        onSelectedChange={setSelected}
        onFilterChange={setFilter}
        footer={
          <div className="width-full d-flex flex-justify-end gap-2">
            <Button size="small" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button
              size="small"
              variant="primary"
              onClick={() => {
                setOpen(false)
                submitSelectedReferences()
              }}
            >
              Start chat
            </Button>
          </div>
        }
        message={
          filteredItems.length === 0
            ? {
                title: 'No files found',
                body: 'Try a different search term',
                variant: 'empty',
              }
            : undefined
        }
      />
    </FeatureFlags>
  )
})
