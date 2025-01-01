import {
  type PropsWithPartialAnchor,
  type ReactPartialAnchorProps,
  useExternalAnchor,
} from '@github-ui/react-core/react-partial-anchor'
import type {
  BranchNextStep,
  BranchType,
  CreateBranchDialogProps as CreateBranchDialogComponentProps,
} from '@github-ui/code-scanning-shared/components/CreateBranchDialog'
import {BranchNextStepLocal} from '@github-ui/code-scanning-shared/components/BranchNextStepLocal'
import {BranchNextStepDesktop} from '@github-ui/code-scanning-shared/components/BranchNextStepDesktop'
import {BranchNextStepFlashes} from '@github-ui/code-scanning-shared/components/BranchNextStepFlashes'
import {CreateBranchDialog as CreateBranchDialogComponent} from '@github-ui/code-scanning-shared/components/CreateBranchDialog'
import type {PullRequest} from '@github-ui/code-scanning-shared/types/pull-request'
import {useEffect, useState} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {useNavigate} from '@github-ui/use-navigate'
import {pullRequestPath} from '@github-ui/paths'

type CreateBranchDialogProps = CreateBranchDialogComponentProps & ReactPartialAnchorProps

const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()

export function CreateBranchDialog(props: CreateBranchDialogProps) {
  if (props.reactPartialAnchor) {
    return <ExternallyAnchoredCreateBranchDialog {...props} reactPartialAnchor={props.reactPartialAnchor} />
  }

  return <CreateBranchDialogComponent {...props} />
}

function ExternallyAnchoredCreateBranchDialog(props: PropsWithPartialAnchor<CreateBranchDialogComponentProps>) {
  const [branchNextStep, setBranchNextStep] = useState<BranchNextStep>('none')
  const [newBranchName, setNewBranchName] = useState<string | null>(null)
  const [errorMessages, setErrorMessages] = useState<string[]>([])

  const {ref: anchorRef, open, setOpen} = useExternalAnchor(props.reactPartialAnchor)

  const branchType = anchorRef.current?.getAttribute('data-branch-type') as BranchType
  const repository = props.repository
  const navigate = useNavigate()

  // Note: Since CreateBranchDialogComponent is used as a standalone component,
  // we need to handle the onClose logic here and make sure we navigate to the correct path
  // See ui/packages/security-campaigns/components/RepoAlertsList.tsx:70
  const handleCloseBranch = (
    nextStep: BranchNextStep,
    branchName: string | null,
    pullRequest: PullRequest | null,
    newErrorMessages?: string[],
  ) => {
    if (nextStep === 'pr' && pullRequest) {
      navigate(
        pullRequestPath({
          repo: pullRequest.repository,
          number: pullRequest.number,
        }),
      )
    } else {
      setOpen(false)
      setNewBranchName(branchName)
      setBranchNextStep(nextStep)
      setErrorMessages(newErrorMessages ?? [])
    }
  }

  const handleBranchNextStepDialogClose = () => {
    setBranchNextStep('none')
  }

  useEffect(() => {
    const handleOpenCreateBranchDialog = () => setOpen(true)
    document.addEventListener('openCreateBranchDialog', handleOpenCreateBranchDialog)
    return () => {
      document.removeEventListener('openCreateBranchDialog', handleOpenCreateBranchDialog)
    }
  })

  return (
    <RelayEnvironmentProvider environment={relayEnvironment}>
      {open && (
        <CreateBranchDialogComponent
          {...props}
          onClose={handleCloseBranch}
          returnFocusRef={anchorRef}
          branchType={branchType}
        />
      )}
      {branchNextStep === 'local' && (
        <BranchNextStepLocal
          branch={newBranchName}
          onClose={handleBranchNextStepDialogClose}
          flashes={<BranchNextStepFlashes errorMessages={errorMessages} />}
        />
      )}
      {branchNextStep === 'desktop' && (
        <BranchNextStepDesktop
          owner={repository.ownerLogin}
          repository={repository.name}
          branch={newBranchName}
          onClose={handleBranchNextStepDialogClose}
          flashes={<BranchNextStepFlashes errorMessages={errorMessages} />}
        />
      )}
    </RelayEnvironmentProvider>
  )
}
