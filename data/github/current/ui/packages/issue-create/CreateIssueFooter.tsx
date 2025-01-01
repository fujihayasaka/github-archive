import {Box, Button, Checkbox, FormControl, Link, Text, type SxProp} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {BUTTON_LABELS} from './constants/buttons'
import {TEST_IDS} from './constants/test-ids'
import {LABELS} from './constants/labels'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {issuePath} from '@github-ui/paths'
import {useEffect, useRef, useState} from 'react'
import {InfoIcon} from '@primer/octicons-react'
import {CommandButton, type CommandId, GlobalCommands} from '@github-ui/ui-commands'

import styles from './CreateIssueFooter.module.css'
import {clsx} from 'clsx'

type CreateIssueFooterProps = {
  className?: string
  hideCreateMore?: boolean
  onClose?: () => void
} & SxProp

export const CreateIssueFooter = ({className, sx, hideCreateMore = false, onClose}: CreateIssueFooterProps) => {
  const {
    createMore,
    setCreateMore,
    createMoreCreatedPath,
    onCreateAction,
    isSubmitting,
    isFileUploading,
    isSubIssue,
    optionConfig: {insidePortal},
  } = useIssueCreateConfigContext()

  const handleCheckMoreChange = () => {
    setCreateMore(!createMore)
  }

  const handleCreateMore = () => {
    setCreateMore(true)
    if (!shouldSubmit()) {
      return
    }
    onCreateAction?.current?.onCreate(isSubmitting, true)
  }

  const [createWaitingOnUpload, setCreateWaitingOnUpload] = useState<boolean>(false)
  const buttonRef = useRef<HTMLButtonElement>(null)

  const shouldSubmit = () => {
    if (isSubmitting) {
      return false
    }

    // do not submit if files are still uploading
    if (isFileUploading) {
      setCreateWaitingOnUpload(true)
      return false
    }

    return true
  }

  const handleSubmit = async () => {
    if (!shouldSubmit()) {
      return
    }

    onCreateAction?.current?.onCreate(isSubmitting, createMore)
  }

  // runs when isFileUploading changes
  useEffect(() => {
    // if the file is not uploading anymore and the submit button was clicked and is not currently submitting, click is emitted
    if (buttonRef.current && !isFileUploading && !isSubmitting && createWaitingOnUpload) {
      setCreateWaitingOnUpload(false)
      buttonRef.current.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}))
    }
  }, [isFileUploading, isSubmitting, createWaitingOnUpload])

  const commands: Partial<Record<CommandId, () => void>> = {
    'github:submit-form': handleSubmit,
  }

  if (!hideCreateMore) {
    commands['issue-create:submit-and-create-more'] = handleCreateMore
  }

  return (
    <Box className={clsx(styles.container, className)} sx={{display: 'flex', flexDirection: 'column'}}>
      <GlobalCommands commands={commands} />
      {createWaitingOnUpload && (
        <Box
          sx={{
            color: 'fg.muted',
            display: 'flex',
            alignItems: 'center',
            gap: 1,
            mb: 2,
            justifyContent: 'flex-end',
          }}
        >
          <Octicon icon={InfoIcon} size={16} />
          <Text sx={{font: 'var(--text-body-shorthand-medium)'}}>{LABELS.fileUploadWarning}</Text>
        </Box>
      )}
      <Box
        sx={{
          width: '100%',
          display: 'flex',
          justifyContent: 'flex-end',
          columnGap: 4,
          rowGap: 3,
          alignItems: 'center',
          flexWrap: 'wrap',
          ...sx,
        }}
      >
        {!hideCreateMore && (
          <Box
            sx={{
              display: 'flex',
              gap: 2,
              alignItems: 'center',
              ml: insidePortal ? 0 : 2,
              flexGrow: 1,
              justifyContent: ['flex-start', 'flex-start', 'flex-end', 'flex-end'],
              flexWrap: 'wrap',
              rowGap: 1,
            }}
          >
            <FormControl sx={{display: 'flex', alignItems: 'center', '> :first-child': {display: 'contents'}}}>
              <Checkbox
                data-testid={TEST_IDS.createMoreIssuesCheckbox}
                checked={createMore}
                onChange={handleCheckMoreChange}
                className={styles.Checkbox}
              />
              <FormControl.Label>
                {isSubIssue ? BUTTON_LABELS.createMoreSubIssues : BUTTON_LABELS.createMore}
              </FormControl.Label>
            </FormControl>
            <div
              data-testid={TEST_IDS.issueCreatedAnnouncement}
              className="sr-only"
              aria-live="polite"
              aria-atomic="true"
              role="status"
            >
              {createMoreCreatedPath.number ? LABELS.lastIssueCreated(createMoreCreatedPath.number) : null}
            </div>
            {createMoreCreatedPath.number ? (
              <>
                <Text sx={{color: 'fg.muted', display: ['none', 'block', 'block', 'block']}}>·</Text>
                <Link
                  href={issuePath({
                    owner: createMoreCreatedPath.owner,
                    repo: createMoreCreatedPath.repo,
                    issueNumber: createMoreCreatedPath.number,
                  })}
                  data-testid={TEST_IDS.issueCreatedLink}
                >
                  {LABELS.lastIssueCreated(createMoreCreatedPath.number)}
                </Link>
              </>
            ) : null}
          </Box>
        )}
        <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
          {onClose && <Button onClick={() => onClose()}>{BUTTON_LABELS.cancel}</Button>}
          <CommandButton
            commandId="github:submit-form"
            variant="primary"
            inactive={isSubmitting || isFileUploading}
            data-testid={TEST_IDS.createIssueButton}
            ref={buttonRef}
            showKeybindingHint
          >
            {BUTTON_LABELS.create}
          </CommandButton>
        </Box>
      </Box>
    </Box>
  )
}
