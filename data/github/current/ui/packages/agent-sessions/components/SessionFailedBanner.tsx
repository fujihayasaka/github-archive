import {Banner} from '@primer/react/experimental'
import {useCurrentRepository} from '@github-ui/current-repository'
import {generateWorkflowRunLink} from '../utils/generate-actions-link'

interface SessionFailedBannerProps {
  errorMessage: string | null
  workflowRunId: number | null
}

export function SessionFailedBanner({errorMessage, workflowRunId}: SessionFailedBannerProps) {
  const {ownerLogin, name: repoName} = useCurrentRepository()
  const defaultErrorMessage = 'An unexpected error occurred. For more details, see the detailed logs in GitHub Actions.'
  const sessionFailedError = errorMessage || defaultErrorMessage
  const workflowRunLink = generateWorkflowRunLink(ownerLogin, repoName, workflowRunId)

  return (
    <Banner
      aria-label="Session Error"
      title="Copilot stopped work due to an error"
      description={sessionFailedError}
      variant="critical"
      primaryAction={
        workflowRunLink && (
          <Banner.PrimaryAction as="a" href={workflowRunLink}>
            View detailed logs
          </Banner.PrimaryAction>
        )
      }
    />
  )
}
