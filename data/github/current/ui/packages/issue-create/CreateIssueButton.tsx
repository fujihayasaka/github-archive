import {Button, type ButtonProps} from '@primer/react'
import {Suspense, useCallback, useMemo, useState} from 'react'

import {CreateIssueDialogEntryInternal, type CreateIssueDialogEntryProps} from './dialog/CreateIssueDialogEntry'
import {CreateIssueButtonLoading} from './CreateIssueButtonLoading'
import {loginPath} from './utils/urls'
import {GlobalCommands} from '@github-ui/ui-commands'
import {useNavigate} from '@github-ui/use-navigate'
import {isLoggedIn} from '@github-ui/client-env'

export type CreateIssueButtonProps = {
  label: string
  size?: 'small' | 'medium'
  isDialogOpenByDefault?: boolean
} & Omit<CreateIssueDialogEntryProps, 'setIsCreateDialogOpen' | 'isCreateDialogOpen'>

export const CreateIssueButton = ({label, size = 'medium', ...props}: CreateIssueButtonProps): JSX.Element | null => {
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
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
    return (
      <>
        {isViewerLoggedIn && <GlobalCommands commands={{'issue-create:new': openDialog}} />}
        <RenderedCreateButton
          size={size}
          label={label}
          onClick={onCreateIssueShortcutClick}
          optionConfig={props.optionConfig}
        />
      </>
    )
  }, [isViewerLoggedIn, openDialog, size, label, onCreateIssueShortcutClick, props.optionConfig])

  if (!isCreateDialogOpen) return renderedButton

  return (
    <Suspense fallback={<CreateIssueButtonLoading label={label} size={size} />}>
      {renderedButton}

      <CreateIssueDialogEntryInternal
        isCreateDialogOpen={isCreateDialogOpen}
        setIsCreateDialogOpen={setIsCreateDialogOpen}
        {...props}
      />
    </Suspense>
  )
}

type RenderedCreateButtonProps = {
  label: string
  size?: 'small' | 'medium'
  onClick: (e: React.MouseEvent) => void
} & Pick<CreateIssueButtonProps, 'optionConfig'>

const RenderedCreateButton = ({size, label, onClick, optionConfig}: RenderedCreateButtonProps) => {
  const buttonHrefProps = useMemo(() => {
    if (!isLoggedIn()) {
      return {
        as: 'a',
        href: loginPath(),
        target: '_blank',
      } as Partial<ButtonProps>
    } else if (optionConfig?.scopedRepository) {
      const href = `/${optionConfig.scopedRepository.owner}/${optionConfig.scopedRepository.name}/issues/new/choose`
      return {
        as: 'a',
        href,
        target: '_blank',
      } as Partial<ButtonProps>
    } else {
      // on issue#dashboard there is no href - when we click on the button it's a no-op
      // until React is fully loaded and we can render the issue create dialog
      return {}
    }
  }, [optionConfig?.scopedRepository])

  // we want to default to the underlying anchor functionality when the user is holding down the cmd or ctrl key
  // and therefore ignore the custom onClick functionality - expect on issue#dashboard where we always want to
  // open the dialog
  const ignoreOnClickIfCmdOrCtrlPressed = (e: React.MouseEvent, clickHandler: (e: React.MouseEvent) => void) => {
    const isIssueDashboard = !optionConfig?.scopedRepository
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if ((!e.ctrlKey && !e.metaKey) || isIssueDashboard) {
      clickHandler(e)
    }

    // ..bubble down to the underlying anchor functionality
  }

  return (
    <Button
      size={size}
      variant={'primary'}
      onClick={(e: React.MouseEvent) => ignoreOnClickIfCmdOrCtrlPressed(e, onClick)}
      {...buttonHrefProps}
    >
      {label}
    </Button>
  )
}
