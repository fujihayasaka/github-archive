import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {SelectPanel} from '@primer/react/experimental'
import {Suspense, memo, useEffect, useRef, useState, type ComponentProps} from 'react'
import {DiffEntriesList} from './DiffEntriesList'

interface DiffHeaderAskCopilotButton {
  anchorProps: ComponentProps<typeof SelectPanel.Button>
  onSubmit: (references: FileDiffReference[]) => void
  pullRequestId: string
}

export const AskCopilotDiffEntriesSelectPanel = memo(function CopilotChatDiffHeaderButton({
  anchorProps,
  onSubmit,
  pullRequestId,
}: DiffHeaderAskCopilotButton) {
  const [filter, setFilter] = useState('')
  const [selectedReferences, setSelectedReferences] = useState<ReadonlyMap<string, FileDiffReference>>(() => new Map())

  const containerRef = useRef<HTMLDivElement>(null)
  const anchorRef = useRef<HTMLButtonElement>(null)

  // Hack alert: SelectPanel does not automatically adjust when it's too close to the edge of the screen so we have to
  // change the orientation in an effect
  // FIXME: get rid of this when https://github.com/primer/react/issues/3919 is resolved
  useEffect(function positionDialogAtAnchorEnd() {
    const container = containerRef.current
    const anchorRect = anchorRef.current?.getBoundingClientRect()
    const dialog = container?.querySelector('dialog')

    if (!anchorRect || !dialog) return

    dialog.style.left = `auto`
    dialog.style.right = `${document.body.clientWidth - anchorRect.right}px`
  })

  // Gross hack alert: change the save button text because it's not supported yet in the API
  // FIXME: get rid of this when https://github.com/github/primer/issues/2645 is resolved
  useEffect(function changeSaveButtonText() {
    const saveButton = containerRef.current?.querySelector('dialog button[type="submit"]')
    if (saveButton) saveButton.textContent = 'Start chat'
  })

  const submitSelectedReferences = () => onSubmit(Array.from(selectedReferences.values()))

  return (
    <div ref={containerRef}>
      <SelectPanel title="Select files to discuss" onSubmit={submitSelectedReferences} anchorRef={anchorRef}>
        <SelectPanel.Button {...anchorProps} />

        <SelectPanel.Header>
          <SelectPanel.SearchInput onChange={e => setFilter(e.target.value)} />
        </SelectPanel.Header>

        <Suspense fallback={<SelectPanel.Loading>Loading files…</SelectPanel.Loading>}>
          <DiffEntriesList
            pullRequestId={pullRequestId}
            filter={filter}
            selectedReferences={selectedReferences}
            onSelectedReferencesChange={setSelectedReferences}
            emptyState={
              <SelectPanel.Message variant="empty" title="No files found">
                Try a different search term
              </SelectPanel.Message>
            }
          />
        </Suspense>

        <SelectPanel.Footer />
      </SelectPanel>
    </div>
  )
})
