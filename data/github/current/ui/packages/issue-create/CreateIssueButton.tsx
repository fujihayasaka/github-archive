import {Button, type ButtonProps} from '@primer/react'
import {forwardRef, Suspense, useCallback, useMemo, useRef, useState} from 'react'

import type {CreateIssueDialogEntryProps} from './dialog/CreateIssueDialogEntry'
import {CreateIssueButtonLoading} from './CreateIssueButtonLoading'
import {loginPath} from './utils/urls'
import {GlobalCommands} from '@github-ui/ui-commands'
import {useNavigate} from '@github-ui/use-navigate'
import {isLoggedIn} from '@github-ui/client-env'
import {CreateIssueDialogEntryInternal} from './dialog/CreateIssueDialogEntry'

export type CreateIssueButtonProps = {
  label: string
  size?: 'small' | 'medium'
  isDialogOpenByDefault?: boolean
} & Omit<CreateIssueDialogEntryProps, 'setIsCreateDialogOpen' | 'isCreateDialogOpen'>

export const CreateIssueButton = ({label, size = 'medium', ...props}: CreateIssueButtonProps): JSX.Element | null => {
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [isNavigatingToNew, setIsNavigatingToNew] = useState(false)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const navigate = useNavigate()
  const isViewerLoggedIn = isLoggedIn()

  const openDialog = useCallback(() => {
    if (isViewerLoggedIn) {
      setIsCreateDialogOpen(true)
    } else {
      navigate(loginPath())
    }
  }, [isViewerLoggedIn, navigate])

  const onCreateIssueShortcutClick = useCallback(
    (event: React.MouseEvent) => {
      event.preventDefault()
      event.stopPropagation()
      openDialog()
    },
    [openDialog],
  )

  const renderedButton = useMemo(() => {
    if (isNavigatingToNew) {
      return <CreateIssueButtonLoading label={label} size={size} />
    }
    return (
      <>
        {isViewerLoggedIn && <GlobalCommands commands={{'issue-create:new': openDialog}} />}
        <RenderedCreateButton
          ref={buttonRef}
          size={size}
          label={label}
          onClick={onCreateIssueShortcutClick}
          optionConfig={props.optionConfig}
        />
      </>
    )
  }, [isNavigatingToNew, props.optionConfig, isViewerLoggedIn, openDialog, size, label, onCreateIssueShortcutClick])

  if (!isCreateDialogOpen) return renderedButton

  const dialogProps = {
    isCreateDialogOpen,
    setIsCreateDialogOpen,
    setIsNavigatingToNew,
    canBypassTemplateSelection: true,
    isNavigatingToNew,
    returnFocusRef: buttonRef,
    ...props,
  }

  return (
    <Suspense fallback={<CreateIssueButtonLoading label={label} size={size} />}>
      {renderedButton}
      <CreateIssueDialogEntryInternal {...dialogProps} />
    </Suspense>
  )
}

type RenderedCreateButtonProps = {
  label: string
  size?: 'small' | 'medium'
  onClick: (e: React.MouseEvent) => void
} & Pick<CreateIssueButtonProps, 'optionConfig'>

const RenderedCreateButton = forwardRef<HTMLButtonElement, RenderedCreateButtonProps>(
  ({size, label, onClick, optionConfig}, ref) => {
    const buttonHrefProps = useMemo(() => {
      if (!isLoggedIn()) {
        return {
          as: 'a',
          href: loginPath(),
          target: '_blank',
        } as Partial<ButtonProps>
      } else if (optionConfig?.issueCreateArguments?.repository) {
        const {owner, name} = optionConfig.issueCreateArguments.repository
        return {
          as: 'a',
          href: `/${owner}/${name}/issues/new/choose`,
          target: '_blank',
        } as Partial<ButtonProps>
      } else {
        // on issue#dashboard there is no href - when we click on the button it's a no-op
        // until React is fully loaded and we can render the issue create dialog
        return {}
      }
    }, [optionConfig?.issueCreateArguments?.repository])

    // we want to default to the underlying anchor functionality when the user is holding down the cmd or ctrl key
    // and therefore ignore the custom onClick functionality - expect on issue#dashboard where we always want to
    // open the dialog
    const ignoreOnClickIfCmdOrCtrlPressed = (e: React.MouseEvent, clickHandler: (e: React.MouseEvent) => void) => {
      const isIssueDashboard = !optionConfig?.issueCreateArguments?.repository
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if ((!e.ctrlKey && !e.metaKey) || isIssueDashboard) {
        clickHandler(e)
      }

      // ..bubble down to the underlying anchor functionality
    }

    return (
      <Button
        ref={ref}
        size={size}
        variant={'primary'}
        onClick={(e: React.MouseEvent) => ignoreOnClickIfCmdOrCtrlPressed(e, onClick)}
        {...buttonHrefProps}
      >
        {label}
      </Button>
    )
  },
)

RenderedCreateButton.displayName = 'RenderedCreateButton'
