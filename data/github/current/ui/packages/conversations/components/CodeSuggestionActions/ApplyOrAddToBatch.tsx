import {useAnalytics} from '@github-ui/use-analytics'
import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Button, ButtonGroup, IconButton} from '@primer/react'
import {type RefObject, useCallback, useRef, useState} from 'react'

import type {CommentingImplementation, SuggestedChange} from '../../types'

type ApplicationMethod = {
  text: string
  inactive?: boolean
  inactiveReason?: string
}
type ApplicationMethods = {
  addSuggestionToBatch: ApplicationMethod
  applySuggestion: ApplicationMethod
}

const applicationMethods: ApplicationMethods = {
  applySuggestion: {text: 'Apply suggestion'},
  addSuggestionToBatch: {
    text: 'Add suggestion to batch',
    inactive: true,
    inactiveReason: 'This feature is not supported yet.',
  },
}

export function ApplyOrAddToBatch({
  commentingImplementation,
  onOpenDialog,
  suggestedChange,
}: {
  commentingImplementation: CommentingImplementation
  onOpenDialog: (returnFocusRef?: RefObject<HTMLElement>) => void
  suggestedChange: SuggestedChange
}) {
  const {sendAnalyticsEvent} = useAnalytics()
  const [selectedButtonApplicationMethod, setSelectedButtonApplicationMethod] = useState<ApplicationMethod>(
    applicationMethods.applySuggestion,
  )
  const [isActionMenuOpen, setIsActionMenuOpen] = useState(false)
  const iconButtonRef = useRef<HTMLButtonElement>(null)
  const returnFocusRef = useRef<HTMLButtonElement>(null)

  const toggleActionMenuOpen = () => setIsActionMenuOpen(!isActionMenuOpen)
  const {addSuggestedChangeToPendingBatch} = commentingImplementation

  const handlePrimaryButtonClick = useCallback(() => {
    if (selectedButtonApplicationMethod === applicationMethods.addSuggestionToBatch) {
      addSuggestedChangeToPendingBatch(suggestedChange)
      sendAnalyticsEvent('comments.add_suggested_change_to_batch', 'ADD_SUGGESTED_CHANGE_TO_BATCH_BUTTON')
    }

    if (selectedButtonApplicationMethod === applicationMethods.applySuggestion) {
      onOpenDialog(returnFocusRef)
    }
  }, [
    addSuggestedChangeToPendingBatch,
    onOpenDialog,
    selectedButtonApplicationMethod,
    sendAnalyticsEvent,
    suggestedChange,
  ])

  return (
    <Box sx={{display: 'flex', flexDirection: 'row-reverse'}}>
      <ButtonGroup>
        <Button variant="primary" onClick={handlePrimaryButtonClick} ref={returnFocusRef}>
          {selectedButtonApplicationMethod.text}
        </Button>
        <ActionMenu anchorRef={iconButtonRef} open={isActionMenuOpen} onOpenChange={toggleActionMenuOpen}>
          <ActionMenu.Anchor>
            <IconButton
              ref={iconButtonRef}
              aria-haspopup="true"
              aria-label="More suggestion batching options"
              icon={TriangleDownIcon}
              size="medium"
              variant="primary"
              onClick={toggleActionMenuOpen}
            />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay width="medium">
            <ActionList selectionVariant="single">
              {(Object.keys(applicationMethods) as [keyof ApplicationMethods]).map(key => {
                const method = applicationMethods[key]
                return (
                  <ActionList.Item
                    selected={selectedButtonApplicationMethod === method}
                    key={key}
                    onSelect={() => setSelectedButtonApplicationMethod(method)}
                    inactiveText={method.inactiveReason}
                  >
                    {method.text}
                  </ActionList.Item>
                )
              })}
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </ButtonGroup>
    </Box>
  )
}
