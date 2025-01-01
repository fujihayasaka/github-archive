import {
  type PropsWithPartialAnchor,
  type ReactPartialAnchorProps,
  useExternalAnchor,
} from '@github-ui/react-core/react-partial-anchor'
import type {
  BranchNextStep,
  BranchType,
  CreateBranchDialogProps as CreateBranchDialogComponentProps,
} from '@github-ui/security-campaigns-shared/components/CreateBranchDialog'
import {BranchNextStepLocal} from '@github-ui/security-campaigns-shared/components/BranchNextStepLocal'
import {BranchNextStepDesktop} from '@github-ui/security-campaigns-shared/components/BranchNextStepDesktop'
import {BranchNextStepFlashes} from '@github-ui/security-campaigns-shared/components/BranchNextStepFlashes'
import {CreateBranchDialog as CreateBranchDialogComponent} from '@github-ui/security-campaigns-shared/components/CreateBranchDialog'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'
import {useState} from 'react'
import {QueryClientProvider} from '@tanstack/react-query'
import {RelayEnvironmentProvider} from 'react-relay'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {useNavigate} from '@github-ui/use-navigate'

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
    pullRequestPath: string | null,
    newErrorMessages?: string[],
  ) => {
    if (nextStep === 'pr' && pullRequestPath) {
      navigate(pullRequestPath)
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

  const [queryClient] = useState(() => getQueryClient())
  return (
    <RelayEnvironmentProvider environment={relayEnvironment}>
      <QueryClientProvider client={queryClient}>
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
      </QueryClientProvider>
    </RelayEnvironmentProvider>
  )
}
