import {Button, Heading, Popover} from '@primer/react'
import {useCallback, useState} from 'react'

import {useDismissNotice, useIsNoticeDismissed} from '../hooks/use-user-notices'
import {useUpdateUserDiffViewPreferenceMutation} from '../hooks/mutations/use-update-user-diff-view-preference-mutation'

const NOTICE_NAME = 'compact_diff_lines'

export function DiffCompactLinesPopover() {
  const isNoticeDismissed = useIsNoticeDismissed(NOTICE_NAME)
  const {dismissNotice} = useDismissNotice(NOTICE_NAME)
  const {mutate: updateUserDiffViewPreference} = useUpdateUserDiffViewPreferenceMutation({
    onSuccess: () => {},
    onError: () => {},
  })
  const [popoverOpen, setPopoverOpen] = useState(true)

  const onEnable = useCallback(() => {
    updateUserDiffViewPreference({lineSpacing: 'compact'})
    setPopoverOpen(false)
    dismissNotice()
  }, [dismissNotice, updateUserDiffViewPreference])

  const onDismiss = useCallback(() => {
    setPopoverOpen(false)
    dismissNotice()
  }, [dismissNotice])

  if (isNoticeDismissed) return null

  return (
    <Popover open={popoverOpen} caret="top-right" sx={{top: '60px', right: '-4px'}}>
      <Popover.Content className="d-flex flex-column gap-2" sx={{minWidth: '260px', width: '40%'}}>
        <Heading
          sx={{
            fontSize: 2,
          }}
          as="h2"
        >
          Customizable line height
        </Heading>
        <p>
          The default line height has been increased for improved accessibility. You can choose to enable a more compact
          line height from the view settings menu.
        </p>
        <div className="d-flex gap-2 flex-row w-full flex-wrap">
          <Button onClick={onEnable} sx={{flexShrink: 0, flexGrow: 1}}>
            Enable compact line height
          </Button>
          <Button onClick={onDismiss} variant="invisible" sx={{color: 'accent.fg', flexGrow: 1}} alignContent="center">
            Dismiss
          </Button>
        </div>
      </Popover.Content>
    </Popover>
  )
}
