import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {ActionMenu, AnchoredOverlay, Button} from '@primer/react'
import type React from 'react'
import {useState, useEffect} from 'react'
import {CodeIcon, TriangleDownIcon} from '@primer/octicons-react'

export interface CodeMenuButtonProps {
  isPrimary: boolean
  children: React.ReactNode
  size?: 'small' | 'large' | 'medium'
  onOpenChange?: (open: boolean) => void
}

export const CodeMenuButton = ({isPrimary, children, size, onOpenChange}: CodeMenuButtonProps) => {
  const accessibleCodeButton = useFeatureFlag('accessible_code_button')
  const [showPopover, setShowPopover] = useState(false)

  useEffect(() => {
    if (!accessibleCodeButton || !onOpenChange) return

    onOpenChange(showPopover)

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showPopover, accessibleCodeButton])

  if (accessibleCodeButton)
    return (
      <AnchoredOverlay
        align="end"
        focusZoneSettings={{disabled: true}}
        open={showPopover}
        onOpen={() => setShowPopover(true)}
        onClose={() => setShowPopover(false)}
        renderAnchor={buttonProps => {
          return (
            <Button
              {...buttonProps}
              variant={isPrimary ? 'primary' : undefined}
              leadingVisual={() => <CodeIcon className="hide-sm" />}
              trailingVisual={() => <TriangleDownIcon />}
              size={size ? size : 'medium'}
            >
              Code
            </Button>
          )
        }}
      >
        {children}
      </AnchoredOverlay>
    )

  return (
    <ActionMenu>
      <ActionMenu.Button
        variant={isPrimary ? 'primary' : undefined}
        leadingVisual={() => <CodeIcon className="hide-sm" />}
        size={size ? size : 'medium'}
      >
        Code
      </ActionMenu.Button>
      <ActionMenu.Overlay width="auto" align="end">
        {children}
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
