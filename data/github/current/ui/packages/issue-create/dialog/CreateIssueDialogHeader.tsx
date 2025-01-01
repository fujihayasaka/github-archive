import {CopyIcon, ScreenFullIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import type {DialogHeaderProps} from '@primer/react/experimental'
import {Dialog} from '@primer/react/experimental'
import {useCallback, useMemo} from 'react'

import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {appendChooseToBasePath} from '../utils/urls'
import {noop} from '@github-ui/noop'
import {LABELS} from '../constants/labels'
import {BUTTON_LABELS} from '../constants/buttons'
import {useIssueCreateConfigContext} from '../contexts/IssueCreateConfigContext'
import {DisplayMode} from '../utils/display-mode'
import {useIssueCreateDataContext} from '../contexts/IssueCreateDataContext'
import {IssueCreationKind} from '../utils/model'
import {CommandIconButton, GlobalCommands} from '@github-ui/ui-commands'

type CreateIssueDialogHeaderProps = {
  navigate: (url: string) => void
} & DialogHeaderProps

export const CreateIssueDialogHeader = ({navigate, dialogLabelId, onClose}: CreateIssueDialogHeaderProps) => {
  const {displayMode, optionConfig, isSubIssue} = useIssueCreateConfigContext()
  const {repository, repositoryAbsolutePath, template} = useIssueCreateDataContext()
  const onCloseClick = useCallback(() => {
    onClose('close-button')
  }, [onClose])

  const chooseUrlForCopy = useMemo(() => appendChooseToBasePath(repositoryAbsolutePath), [repositoryAbsolutePath])

  // For template selection, we want to show a "Copy URL" button, while for issue creation we can show a fullscreen navigation.
  const showCopyUrlButton = displayMode === DisplayMode.TemplatePicker && repository !== undefined
  const showFullScreenButton =
    displayMode === DisplayMode.IssueCreation &&
    optionConfig.showFullScreenButton &&
    navigate !== noop &&
    repository !== undefined

  const navigateToFullscreen = () => {
    if (!showFullScreenButton) {
      return
    }

    const baseUrl = `/${repository.nameWithOwner}/issues/new`
    const templateFileName = !template || template.kind === IssueCreationKind.BlankIssue ? undefined : template.fileName
    const link = templateFileName ? `${baseUrl}?template=${encodeURIComponent(templateFileName)}` : baseUrl
    navigate(link)
  }

  const dialogTitle = useMemo(() => {
    if (displayMode === DisplayMode.TemplatePicker || !repository?.nameWithOwner) {
      const initialTitle = optionConfig.issueCreateArguments?.initialValues?.title
      return LABELS.issueCreateDialogTitleTemplatePane + (initialTitle ? ` - "${initialTitle}"` : '')
    }

    // If it's a blank issue then we don't want to show the template suffix
    const templateName = !template || template.kind === IssueCreationKind.BlankIssue ? undefined : template.name

    // If we are adding this as a child of another issue, then we want to update the label to match
    const relationType = isSubIssue ? 'sub-issue' : 'issue'

    if (displayMode === DisplayMode.IssueDuplication) {
      return LABELS.issueCreateDialogTitleDuplicationPane(repository.nameWithOwner, relationType)
    }

    return LABELS.issueCreateDialogTitleCreationPane(repository.nameWithOwner, templateName, relationType)
  }, [displayMode, isSubIssue, repository?.nameWithOwner, template, optionConfig])

  return (
    <Dialog.Header>
      <GlobalCommands commands={{'issue-create:open-fullscreen': navigateToFullscreen}} />
      <Box sx={{display: 'flex'}}>
        <Box sx={{display: 'flex', flexDirection: 'column', flexGrow: 1, px: 2, py: '6px'}}>
          <Dialog.Title id={dialogLabelId}>{dialogTitle}</Dialog.Title>
        </Box>
        {showCopyUrlButton && (
          <CopyToClipboardButton
            sx={{pt: '2px', borderRadius: '4px'}}
            textToCopy={chooseUrlForCopy}
            ariaLabel={BUTTON_LABELS.copyUrl}
            icon={CopyIcon}
            tooltipProps={{direction: 'n'}}
          />
        )}
        {showFullScreenButton && (
          <CommandIconButton
            sx={{pt: '2px', borderRadius: '4px'}}
            variant="invisible"
            commandId="issue-create:open-fullscreen"
            icon={ScreenFullIcon}
          />
        )}
        <Dialog.CloseButton onClose={onCloseClick} />
      </Box>
    </Dialog.Header>
  )
}
