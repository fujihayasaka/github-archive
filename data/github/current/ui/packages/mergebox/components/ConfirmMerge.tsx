import {useAnalytics} from '@github-ui/use-analytics'
import {AlertFillIcon} from '@primer/octicons-react'
import {Box, Button, FormControl, Heading, Spinner, Text, Textarea, TextInput} from '@primer/react'
import {useEffect, useRef, useState} from 'react'

import {useEnableAutoMergeMutation} from '../hooks/mutations/use-enable-auto-merge-mutation'
import {useMergeMutation} from '../hooks/mutations/use-merge-mutation'
import {mergeButtonText} from '../helpers/merge-button-text'
import {MergeMethod} from '../types'
import useSafeState from '@github-ui/use-safe-state'
import {FlashError} from '@github-ui/flash-error'
import {MergeError} from '../helpers/merge-error'
import {MergeSectionActions} from './sections/merge-section/MergeSectionActions'

/**
 * Displays an error message if the merge fails
 * Per https://primer.style/ui-patterns/loading#button-loading-state,
 * we focus the heading of the error message when the error appears
 */
function MergeErrorMessage({errorMessage}: {errorMessage: string; isAutoMergeAllowed?: boolean}) {
  const headingRef = useRef<HTMLHeadingElement>(null)

  useEffect(() => {
    headingRef.current?.focus()
  }, [])

  return (
    <Heading ref={headingRef} as="h2" className="f5 mt-3 d-flex gap-1 fgColor-danger flex-items-center" tabIndex={0}>
      <AlertFillIcon size={14} />
      {errorMessage}
    </Heading>
  )
}

type ConfirmMergeProps = {
  commitAuthorEmail: string
  commitMessageBody: string | null | undefined
  commitMessageHeadline: string | null | undefined
  defaultBranchName: string
  isBypassMerge: boolean
  onCancel: () => void
  selectedMergeMethod: MergeMethod
  isAutoMergeAllowed: boolean
}

/**
 * Renders the confirmation options and inputs for commit header and message for merging
 */
export function ConfirmMerge({
  commitAuthorEmail,
  commitMessageBody,
  commitMessageHeadline,
  defaultBranchName,
  isBypassMerge,
  onCancel,
  selectedMergeMethod,
  isAutoMergeAllowed = false,
}: ConfirmMergeProps) {
  const commitHeaderRef = useRef<HTMLInputElement>(null)
  const confirmMergeButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    commitHeaderRef.current?.focus()
    confirmMergeButtonRef.current?.scrollIntoView({behavior: 'smooth', block: 'nearest'})
  }, [])

  const [commitMessageHeadlineValue, setCommitMessageHeadlineValue] = useState(commitMessageHeadline || '')
  const [commitMessageBodyValue, setCommitMessageBodyValue] = useState(commitMessageBody || '')
  const {sendAnalyticsEvent} = useAnalytics()
  const [errorMessage, setErrorMessage] = useSafeState<string | undefined>()
  const [ruleErrors, setRuleErrors] = useSafeState<string[]>([])

  const {mutate: mergeMutation, isPending: isMergePending} = useMergeMutation({
    onError: (e: Error) => {
      if (e instanceof MergeError && e.ruleErrors.length > 0) {
        setRuleErrors(e.ruleErrors)
        setErrorMessage(undefined)
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
        setErrorMessage(undefined)
      } else {
        setRuleErrors([])
        setErrorMessage(e.message)
      }
    },
  })

  const isPending = isMergePending || isEnableAutoMergePending

  const handleConfirmMerge = () => {
    if (isPending) return

    setErrorMessage(undefined)

    if (isAutoMergeAllowed) {
      enableAutoMergeMutation({
        commitMessage: commitMessageBodyValue,
        commitTitle: commitMessageHeadlineValue,
        mergeMethod: selectedMergeMethod,
      })
      sendAnalyticsEvent('direct_merge_section.confirm_auto_merge', 'MERGEBOX_AUTO_MERGE_CONFIRMATION_BUTTON')
    } else {
      mergeMutation({
        bypassBranchProtections: isBypassMerge,
        commitTitle: commitMessageHeadlineValue,
        commitMessage: commitMessageBodyValue,
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
            <FormControl.Label>Commit header</FormControl.Label>
            <TextInput
              ref={commitHeaderRef}
              block
              defaultValue={commitMessageHeadlineValue}
              onChange={e => setCommitMessageHeadlineValue(e.currentTarget.value)}
            />
          </FormControl>
          <FormControl className="mt-3 width-full">
            <FormControl.Label>Commit message</FormControl.Label>
            <Textarea
              block
              defaultValue={commitMessageBodyValue}
              onChange={e => setCommitMessageBodyValue(e.currentTarget.value)}
            />
          </FormControl>
          <Box sx={{mt: 3}}>
            <Text sx={{color: 'fg.muted', fontSize: 1}}>This commit will be authored by {commitAuthorEmail}.</Text>
          </Box>
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
            aria-describedby={isPending ? 'merging-message' : undefined}
            aria-disabled={isPending}
            inactive={isPending}
            variant={isBypassMerge ? 'danger' : 'primary'}
            onClick={handleConfirmMerge}
          >
            <Box sx={{display: 'flex', alignItems: 'center'}}>
              {isPending && <Spinner size={'small'} sx={{mr: 1}} />}
              <Text sx={{fontSize: 1}}>
                {mergeButtonText({
                  mergeMethod: selectedMergeMethod,
                  confirming: true,
                  isBypassMerge,
                  inProgress: isPending,
                  isAutoMergeAllowed,
                })}
              </Text>
            </Box>
          </Button>
        </MergeSectionActions.Slot>
        <MergeSectionActions.Slot>
          <Button onClick={onCancel}>Cancel</Button>
        </MergeSectionActions.Slot>
      </MergeSectionActions>
      {isPending && (
        <Text aria-busy="true" aria-live="polite" id="merging-message" sx={{display: 'none'}}>
          Merging...
        </Text>
      )}
      {errorMessage && <MergeErrorMessage errorMessage={errorMessage} />}
    </div>
  )
}
