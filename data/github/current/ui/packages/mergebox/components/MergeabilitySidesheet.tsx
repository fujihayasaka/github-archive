import {XIcon} from '@primer/octicons-react'
import {Heading, IconButton, Overlay} from '@primer/react'
import {useRef} from 'react'
import {MergeBoxWithSuspense} from './MergeBox'

interface MergeabilitySidesheetProps {
  mergeabilitySidesheetIsOpen: boolean
  toggleMergeabilitySidesheet: (isOpen: boolean) => void
  mergeStatusButtonRef: React.RefObject<HTMLButtonElement>
  viewerLogin: string
  helpUrl: string
}

/**
 * Renders the merge box in a sidesheet that is triggered from the header
 */
export function MergeabilitySidesheet({
  mergeabilitySidesheetIsOpen,
  toggleMergeabilitySidesheet,
  mergeStatusButtonRef,
  viewerLogin,
  helpUrl,
}: MergeabilitySidesheetProps) {
  const closeButtonRef = useRef<HTMLButtonElement>(null)

  const exitOverlay = () => toggleMergeabilitySidesheet?.(false)

  return (
    <Overlay
      anchorSide="inside-left"
      aria-label="Merge status"
      initialFocusRef={closeButtonRef}
      position="fixed"
      returnFocusRef={mergeStatusButtonRef}
      right={0}
      role="complementary"
      top={0}
      width="xlarge"
      className="py-2 rounded-right-0 height-full"
      sx={{
        display: mergeabilitySidesheetIsOpen ? 'block' : 'none',
        height: '100vh',
        maxHeight: '100vh',
      }}
      onClickOutside={exitOverlay}
      onEscape={exitOverlay}
    >
      <div className="d-flex flex-justify-between flex-items-center my-2 mx-3">
        <Heading as="h3" className="f3 text-bold">
          Merge status
        </Heading>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton
          unsafeDisableTooltip
          ref={closeButtonRef}
          aria-label="Close merge status"
          icon={XIcon}
          variant="invisible"
          onClick={exitOverlay}
        />
      </div>
      <div className="mx-3">
        <MergeBoxWithSuspense helpUrl={helpUrl} viewerLogin={viewerLogin} />
      </div>
    </Overlay>
  )
}
