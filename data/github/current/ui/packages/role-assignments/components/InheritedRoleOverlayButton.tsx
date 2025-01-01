import {testIdProps} from '@github-ui/test-id-props'
import {useRef, useState} from 'react'
import {AnchoredOverlay, IconButton} from '@primer/react'
import {ShieldLockIcon} from '@primer/octicons-react'

export function InheritedRoleOverlayButton() {
  const [isOpen, setOpen] = useState(false)
  const buttonRef = useRef<HTMLButtonElement>(null)

  return (
    <>
      {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
      <IconButton
        ref={buttonRef}
        icon={ShieldLockIcon}
        variant="invisible"
        aria-label="This role cannot be removed"
        onClick={() => setOpen(!isOpen)}
        unsafeDisableTooltip
        {...testIdProps('inherited-assignment-button')}
      />
      <AnchoredOverlay
        open={isOpen}
        onOpen={() => {
          setOpen(true)
        }}
        onClose={() => {
          setOpen(false)
        }}
        renderAnchor={null}
        anchorRef={buttonRef}
        overlayProps={{
          role: 'dialog',
          'aria-modal': true,
          'aria-label': 'Inherited role overlay',
        }}
        width="small"
        side="outside-top"
      >
        <div className="px-3 py-2">
          Inherited roles can only be removed by removing the member or role from the team.
        </div>
      </AnchoredOverlay>
    </>
  )
}
