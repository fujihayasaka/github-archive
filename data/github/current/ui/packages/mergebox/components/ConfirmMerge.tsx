import {useAnalytics} from '@github-ui/use-analytics'
import {Box, Button, FormControl, Select, Text, Textarea, TextInput} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useEffect, useRef, useState} from 'react'
import {announce} from '@github-ui/aria-live'
import {useEnableAutoMergeMutation} from '../hooks/mutations/use-enable-auto-merge-mutation'
import {useMergeMutation} from '../hooks/mutations/use-merge-mutation'
import {mergeButtonText} from '../helpers/merge-button-text'
import {MergeMethod} from '../types'
import useSafeState from '@github-ui/use-safe-state'
import {FlashError} from '@github-ui/flash-error'
import {MergeError} from '../helpers/merge-error'
import {MergeSectionActions} from './sections/merge-section/MergeSectionActions'

function MergeErrorMessage({errorMessage}: {errorMessage?: string}) {
  useEffect(() => {
    if (errorMessage && errorMessage.length > 0) {
      announce(errorMessage)
    }
  }, [errorMessage])
  if (!errorMessage) return null
  return (
    <Banner
      className="mt-3"
      aria-label="Merge error warning banner"
      variant="warning"
      title="Merge error"
      hideTitle
      description={errorMessage}
    />
  )
}

type ConfirmMergeProps = {
  defaultCommitAuthorEmail: string | null | undefined
  commitMessageBody: string | null | undefined
  commitMessageHeadline: string | null | undefined
  defaultBranchName: string
  handleConfirmingMergeInfo: (isConfirming: boolean) => void
  isBypassMerge: boolean
  onCancel: () => void
  selectedMergeMethod: MergeMethod
  isAutoMergeAllowed: boolean
  possibleCommitAuthorEmails: string[]
}

/**
 * Renders the confirmation options and inputs for commit header and message for merging
 */
export function ConfirmMerge({
  defaultCommitAuthorEmail,
  commitMessageBody,
  commitMessageHeadline,
  defaultBranchName,
  handleConfirmingMergeInfo,
  isBypassMerge,
  onCancel,
  selectedMergeMethod,
  isAutoMergeAllowed = false,
  possibleCommitAuthorEmails,
}: ConfirmMergeProps) {
  const commitMessageRef = useRef<HTMLInputElement>(null)
  const confirmMergeButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    commitMessageRef.current?.focus()
    confirmMergeButtonRef.current?.scrollIntoView({behavior: 'smooth', block: 'nearest'})
  }, [])

  const [commitMessageHeadlineValue, setCommitMessageHeadlineValue] = useState(commitMessageHeadline || '')
  const [commitMessageBodyValue, setCommitMessageBodyValue] = useState(commitMessageBody || '')
  const {sendAnalyticsEvent} = useAnalytics()
  const [errorMessage, setErrorMessage] = useSafeState('')
  const [ruleErrors, setRuleErrors] = useSafeState<string[]>([])
  // The server will only return possible commit author emails if the current user can select one.
  const canChooseCommitAuthor = possibleCommitAuthorEmails.length > 0
  // The server should only return null for REBASE
  const defaultCommitAuthorEmailByMergeMethod =
    selectedMergeMethod === MergeMethod.REBASE ? '' : defaultCommitAuthorEmail ? defaultCommitAuthorEmail : ''
  const [commitAuthorEmailValue, setCommitAuthorEmailValue] = useState(defaultCommitAuthorEmailByMergeMethod)

  const {mutate: mergeMutation, isPending: isMergePending} = useMergeMutation({
    onError: (e: Error) => {
      if (e instanceof MergeError && e.ruleErrors.length > 0) {
        setRuleErrors(e.ruleErrors)
      } else {
        setRuleErrors([])
        setErrorMessage(e.message)
      }
    },
  })

  const {mutate: enableAutoMergeMutation, isPending: isEnableAutoMergePending} = useEnableAutoMergeMutation({
    onError: (e: Error) => {
      if (e instanceof MergeError && e.ruleErrors.length > 0) {
        setRuleErrors(e.ruleErrors)
      } else {
        setRuleErrors([])
        setErrorMessage(e.message)
      }
    },
    onSuccess: () => {
      handleConfirmingMergeInfo(false)
    },
  })

  const isPending = isMergePending || isEnableAutoMergePending

  // To resolve an issue where the commit author email is not used for merge, let's begin passing through the author email
  // when a user is selecting a commit author email
  const sendCommitAuthorEmail = canChooseCommitAuthor

  const handleConfirmMerge = () => {
    if (isPending) return

    setErrorMessage('')

    if (isAutoMergeAllowed) {
      enableAutoMergeMutation({
        ...(sendCommitAuthorEmail ? {authorEmail: commitAuthorEmailValue} : {}),
        commitMessage: commitMessageBodyValue,
        commitTitle: commitMessageHeadlineValue,
        mergeMethod: selectedMergeMethod,
      })
      sendAnalyticsEvent('direct_merge_section.confirm_auto_merge', 'MERGEBOX_AUTO_MERGE_CONFIRMATION_BUTTON')
    } else {
      mergeMutation({
        ...(sendCommitAuthorEmail ? {authorEmail: commitAuthorEmailValue} : {}),
        bypassBranchProtections: isBypassMerge,
        commitMessage: commitMessageBodyValue,
        commitTitle: commitMessageHeadlineValue,
        mergeMethod: selectedMergeMethod,
      })
      sendAnalyticsEvent('direct_merge_section.confirm_direct_merge', 'MERGEBOX_DIRECT_MERGE_CONFIRMATION_BUTTON')
    }
  }

  return (
    <div>
      {ruleErrors.length > 0 && (
        <FlashError
          prefix=""
          helpUrl=""
          errorMessageNotUsingPrefix="Repository rule violations found"
          hideRuleErrorsTitle
          ruleErrors={ruleErrors}
        />
      )}
      {selectedMergeMethod !== MergeMethod.REBASE && (
        <>
          <FormControl>
            <FormControl.Label>Commit message</FormControl.Label>
            <TextInput
              ref={commitMessageRef}
              block
              defaultValue={commitMessageHeadlineValue}
              onChange={e => setCommitMessageHeadlineValue(e.currentTarget.value)}
            />
          </FormControl>
          <FormControl className="mt-3 width-full">
            <FormControl.Label>Extended description</FormControl.Label>
            <Textarea
              block
              placeholder="Add an optional extended description…"
              defaultValue={commitMessageBodyValue}
              onChange={e => setCommitMessageBodyValue(e.currentTarget.value)}
              onKeyDown={ev => {
                // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                if (ev.key === 'Enter' && (ev.metaKey || ev.ctrlKey)) {
                  ev.preventDefault()
                  handleConfirmMerge()
                }
              }}
            />
          </FormControl>
          {canChooseCommitAuthor ? (
            <Box sx={{mt: 3}}>
              <FormControl>
                <FormControl.Label>Commit email</FormControl.Label>
                <Select
                  defaultValue={defaultCommitAuthorEmailByMergeMethod}
                  onChange={e => setCommitAuthorEmailValue(e.target.value)}
                  aria-label="Select commit author email"
                >
                  {possibleCommitAuthorEmails.map(email => (
                    <Select.Option key={email} value={email}>
                      {email}
                    </Select.Option>
                  ))}
                </Select>
              </FormControl>
            </Box>
          ) : (
            <Box sx={{mt: 3}}>
              <Text sx={{color: 'fg.muted', fontSize: 1}}>
                This commit will be authored by {defaultCommitAuthorEmailByMergeMethod}.
              </Text>
            </Box>
          )}
        </>
      )}
      {selectedMergeMethod === MergeMethod.REBASE && (
        <Text sx={{color: 'fg.muted', fontSize: 1}}>
          This will rebase your changes and merge them into {defaultBranchName}.
        </Text>
      )}
      <MergeSectionActions className="mt-3">
        <MergeSectionActions.Slot>
          <Button
            ref={confirmMergeButtonRef}
            loading={isPending}
            loadingAnnouncement={mergeButtonText({
              mergeMethod: selectedMergeMethod,
              confirming: true,
              isBypassMerge,
              inProgress: true,
              isAutoMergeAllowed,
            })}
            variant={isBypassMerge ? 'danger' : isAutoMergeAllowed ? 'default' : 'primary'}
            onClick={handleConfirmMerge}
          >
            {mergeButtonText({
              mergeMethod: selectedMergeMethod,
              confirming: true,
              isBypassMerge,
              inProgress: false,
              isAutoMergeAllowed,
            })}
          </Button>
        </MergeSectionActions.Slot>
        <MergeSectionActions.Slot>
          <Button onClick={onCancel}>Cancel</Button>
        </MergeSectionActions.Slot>
      </MergeSectionActions>
      <MergeErrorMessage errorMessage={errorMessage} />
    </div>
  )
}
