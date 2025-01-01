import {useState} from 'react'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {branchPath, userHovercardPath} from '@github-ui/paths'
import {BranchName, Button, Link, Portal, RelativeTime, Spinner} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {RefSelector} from '@github-ui/ref-selector'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {InlineMessage, Tooltip} from '@primer/react/experimental'
import {useQueryClient} from '@github-ui/react-query'
import type {PullRequestState} from './PullRequestStateLabel'
import {useChangeBaseBranchMutation} from '../mutations/use-change-base-branch-mutation'
import styles from './PullRequestHeaderSummary.module.css'
import {getBaseBranchText, getHeadBranchText} from '../utils/branch-label'
import {useHeaderPageDataQueryKey} from '../page-data/loaders/use-header-page-data'
import {useCommitsPageDataQueryKey} from '../page-data/loaders/use-commits-page-data'
import type {PullRequestAppPayload} from '../page-data/payloads/pull-request-app'

export interface PullRequestHeaderSummaryProps {
  author: string
  baseBranch: string
  baseRepositoryDefaultBranch?: string
  baseRepositoryOwnerLogin: string
  baseRepositoryName: string
  canChangeBase?: boolean
  commitsCount: number
  headBranch: string
  headRepositoryOwnerLogin?: string
  headRepositoryName?: string
  isInAdvisoryRepo?: boolean
  isEditing?: boolean
  mergedBy?: string
  mergedTime?: string
  setIsEditing?: (isEditing: boolean) => void
  state: PullRequestState
}

export function PullRequestHeaderSummary({
  author,
  baseBranch,
  baseRepositoryDefaultBranch = '',
  baseRepositoryName = '',
  baseRepositoryOwnerLogin = '',
  canChangeBase = false,
  commitsCount,
  headBranch,
  headRepositoryOwnerLogin = '',
  headRepositoryName = '',
  isInAdvisoryRepo,
  isEditing = false,
  mergedBy,
  mergedTime,
  setIsEditing,
  state,
}: PullRequestHeaderSummaryProps) {
  const queryClient = useQueryClient()
  const {refListCacheKey} = useAppPayload<PullRequestAppPayload>()
  const [isConfirmingChangeBase, setIsConfirmingChangeBase] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')
  const [candidateBaseBranch, setCandidateBaseBranch] = useState('')

  const headerPageDataQueryKey = useHeaderPageDataQueryKey()
  const commitsPageDataQueryKey = useCommitsPageDataQueryKey()
  const {mutate: mutateChangeBaseBranch} = useChangeBaseBranchMutation()

  const onSelectItem = (selectedBaseBranch: string) => {
    setIsConfirmingChangeBase(true)
    setCandidateBaseBranch(selectedBaseBranch)
  }
  const onCancelChangeBase = () => {
    setIsConfirmingChangeBase(false)
    setCandidateBaseBranch('')
    setErrorMessage('')
  }
  const handleChangeBaseError = (message: string) => {
    setIsLoading(false)
    setErrorMessage(message)
  }
  const onConfirmChangeBase = () => {
    setIsLoading(true)
    mutateChangeBaseBranch(
      {newBaseBranch: candidateBaseBranch},
      {
        onError: error => handleChangeBaseError(error.message),
        onSuccess: async () => {
          try {
            await Promise.all([
              // We're using refetchQueries here instead of invalidateQueries in order to ensure that the
              // page data is updated *before* the confirmation dialog is closed, for a smoother overall UX.
              queryClient.refetchQueries({queryKey: headerPageDataQueryKey}, {throwOnError: true}),
              queryClient.refetchQueries({queryKey: commitsPageDataQueryKey}, {throwOnError: true}),
            ])
            setIsLoading(false)
            setIsEditing?.(false)
            setIsConfirmingChangeBase(false)
          } catch {
            handleChangeBaseError('Unable to refetch commits. Please refresh the page.')
          }
        },
      },
    )
  }

  const buttonLabel = isLoading ? null : 'Change base'
  const buttonLeadingVisual = isLoading ? () => <Spinner size="small" /> : null

  const baseBranchText = getBaseBranchText(baseBranch, baseRepositoryOwnerLogin, headRepositoryOwnerLogin)
  const headBranchText = getHeadBranchText(
    baseRepositoryOwnerLogin,
    headRepositoryOwnerLogin,
    headRepositoryName,
    headBranch,
    isInAdvisoryRepo,
  )

  const summaryActor = state === 'MERGED' ? mergedBy : author
  const messageText = getSummaryMessageText(state, commitsCount, summaryActor)

  return (
    <span className="fgColor-muted d-flex flex-items-center overflow-hidden no-wrap" style={{gap: '0px 4px'}}>
      {summaryActor ? (
        <>
          <Link
            inline
            className="fgColor-muted text-bold"
            data-hovercard-url={userHovercardPath({owner: summaryActor})}
            href={`/${summaryActor}`}
          >
            {summaryActor}
          </Link>{' '}
        </>
      ) : null}
      {messageText}
      {canChangeBase && isEditing ? (
        <>
          <RefSelector
            cacheKey={refListCacheKey}
            canCreate={false}
            closeOnSelect
            currentCommitish={baseBranch}
            defaultBranch={baseRepositoryDefaultBranch}
            hideShowAll
            owner={baseRepositoryOwnerLogin}
            repo={baseRepositoryName}
            types={['branch']}
            onSelectItem={onSelectItem}
          />
          <Portal>
            <Dialog
              aria-labelledby="confirm-change-base-branch"
              isOpen={isConfirmingChangeBase}
              onDismiss={onCancelChangeBase}
            >
              <Dialog.Header id="confirm-change-base-branch">Are you sure you want to change the base?</Dialog.Header>
              <div className="p-3">
                <span>
                  Some commits from the old base branch may be removed from the timeline, and old review comments may
                  become outdated.
                </span>
                {errorMessage && (
                  <InlineMessage className="mt-2" variant="critical">
                    {errorMessage}
                  </InlineMessage>
                )}
                {/* Loading message accessible to screen readers only. See https://primer.style/components/button#button-loading-state */}
                <span className="sr-only" aria-live="polite">
                  {isLoading ? 'Base branch update in progress.' : ''}
                </span>
                <Button
                  // aria-disabled must be not set when false to avoid broken styling
                  alignContent="center"
                  aria-disabled={isLoading ? 'true' : undefined}
                  block
                  className="mt-3"
                  disabled={isLoading}
                  leadingVisual={buttonLeadingVisual}
                  onClick={onConfirmChangeBase}
                  variant="primary"
                >
                  {buttonLabel}
                </Button>
              </div>
            </Dialog>
          </Portal>
        </>
      ) : (
        <PullRequestBranchName
          branch={baseBranch}
          branchText={baseBranchText}
          repositoryName={baseRepositoryName}
          repositoryOwner={baseRepositoryOwnerLogin}
        />
      )}
      <span>from </span>
      <div className="d-flex flex-items-center overflow-hidden">
        <PullRequestBranchName
          branch={headBranch}
          branchText={headBranchText}
          repositoryName={headRepositoryName}
          repositoryOwner={headRepositoryOwnerLogin}
        />
        <CopyToClipboardButton
          ariaLabel="Copy head branch name to clipboard"
          size="small"
          textToCopy={headRepositoryOwnerLogin ? headBranchText : headBranch}
        />
      </div>
      {state === 'MERGED' && <RelativeTime datetime={mergedTime} />}
    </span>
  )
}

function getSummaryMessageText(state: PullRequestState, commitsCount: number, actor?: string) {
  const commitsNumberText = `${commitsCount} ${commitsCount > 1 ? 'commits' : 'commit'}`

  if (state === 'MERGED') {
    if (actor) {
      return `merged ${commitsNumberText} into`
    } else {
      return `${commitsNumberText} merged into`
    }
  } else {
    return `wants to merge ${commitsNumberText} into`
  }
}

function PullRequestBranchName({
  branchText,
  repositoryOwner,
  repositoryName,
  branch,
}: {
  branchText: string
  repositoryName: string
  repositoryOwner: string
  branch: string
}) {
  if (repositoryName && repositoryOwner) {
    const branchUrl = branchPath({owner: repositoryOwner, repo: repositoryName, branch})
    return (
      <Tooltip text={`${repositoryOwner}/${repositoryName}:${branch}`}>
        <BranchName href={branchUrl} className={styles.truncateBranch}>
          {branchText}
        </BranchName>
      </Tooltip>
    )
  } else {
    return (
      <BranchName as="span" className={styles.truncateBranch} title="This repository has been deleted">
        {branchText}
      </BranchName>
    )
  }
}
