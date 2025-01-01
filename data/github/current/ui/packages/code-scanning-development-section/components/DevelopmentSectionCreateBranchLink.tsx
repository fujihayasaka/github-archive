import {Button} from '@primer/react'
import {BranchNextStepLocal} from '@github-ui/code-scanning-shared/components/BranchNextStepLocal'
import {BranchNextStepDesktop} from '@github-ui/code-scanning-shared/components/BranchNextStepDesktop'
import {BranchNextStepFlashes} from '@github-ui/code-scanning-shared/components/BranchNextStepFlashes'

import {
  CreateBranchDialog,
  type BranchNextStep,
  type CreateBranchDialogProps,
} from '@github-ui/code-scanning-shared/components/CreateBranchDialog'
import {useState} from 'react'
import {useNavigate} from '@github-ui/use-navigate'
import type {PullRequest} from '@github-ui/code-scanning-shared/types/pull-request'
import {pullRequestPath} from '@github-ui/paths'

type CreateBranchLinkProps = Pick<
  CreateBranchDialogProps,
  'alertNumbers' | 'alertNumbersWithSuggestedFixes' | 'createPath' | 'repository'
> & {
  alertTitle: string
}

export function DevelopmentSectionCreateBranchLink(props: CreateBranchLinkProps) {
  const {repository, alertNumbersWithSuggestedFixes} = props
  const [showCreateBranchDialog, setShowCreateBranchDialog] = useState(false)
  const [branchNextStep, setBranchNextStep] = useState<BranchNextStep>('none')
  const [newBranchName, setNewBranchName] = useState<string | null>(null)
  const [errorMessages, setErrorMessages] = useState<string[]>([])

  const navigate = useNavigate()

  const openCreateBranchDialog = () => {
    setShowCreateBranchDialog(true)
  }

  const handleCreateBranchDialogClose = (
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
      setShowCreateBranchDialog(false)
      setNewBranchName(branchName)
      setBranchNextStep(nextStep)
      setErrorMessages(newErrorMessages ?? [])
    }
  }

  const handleBranchNextStepDialogClose = () => {
    setBranchNextStep('none')
  }

  return (
    <>
      {alertNumbersWithSuggestedFixes.length > 0 ? (
        <div className="color-fg-muted">
          <Button
            variant="link"
            aria-label="Commit Copilot Autofix to a new branch"
            onClick={openCreateBranchDialog}
            data-testid="development-section-commit-autofix-button"
          >
            Commit Copilot Autofix to a new branch
          </Button>{' '}
          or link a branch or pull request to address this alert.
        </div>
      ) : (
        <div className="color-fg-muted">
          Link a branch, pull request, or{' '}
          <Button
            variant="link"
            aria-label="Create a new branch"
            onClick={openCreateBranchDialog}
            data-testid="development-section-create-branch-button"
          >
            create a new branch
          </Button>{' '}
          to start working on this alert.
        </div>
      )}

      {/* TODO(@aliceclv): We need to refactor the `CreateBranchDialog` to be a standalone component containing the branch next steps */}
      {showCreateBranchDialog && (
        <CreateBranchDialog
          alertNumbers={props.alertNumbers}
          alertNumbersWithSuggestedFixes={props.alertNumbersWithSuggestedFixes}
          createPath={props.createPath}
          repository={props.repository}
          firstAlertWithSuggestedFixTitle={props.alertTitle}
          onClose={handleCreateBranchDialogClose}
          branchType="new"
          isCampaign={false}
          someSelectedAlertsAreClosed={false}
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
    </>
  )
}
