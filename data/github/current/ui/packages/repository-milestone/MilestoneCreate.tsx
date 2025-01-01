import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'

import styles from './MilestoneCreateEdit.module.css'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {MilestoneError} from './MilestoneError'
import {LABELS} from './constants/labels'
import {MilestoneForm} from './components/MilestoneForm'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'
import {goBack} from '@github-ui/history'
import type {MilestoneCreateFormRepositoryQuery$key} from './__generated__/MilestoneCreateFormRepositoryQuery.graphql'
import {useNavigate} from '@github-ui/use-navigate'
import {commitCreateRepositoryMilestoneMutation} from './mutations/create-repository-milestone-mutation'
import {formatFormErrorMessage} from './utils/format-form-error-message'
import {useCallback, useState, type Dispatch, type SetStateAction} from 'react'
import type {CreateMilestoneInput} from './mutations/__generated__/createRepositoryMilestoneMutation.graphql'
import {Link} from '@primer/react'

type MilestoneCreateProps = {
  repository: MilestoneCreateFormRepositoryQuery$key
  optionConfig?: UserSettingsOptionConfig
}

export function MilestoneCreate(props: MilestoneCreateProps) {
  const navigate = useNavigate()
  const environment = useRelayEnvironment()

  const [submissionErrors, setSubmissionErrors] = useState<string | null>(null)

  const repositoryData = useFragment(
    graphql`
      fragment MilestoneCreateFormRepositoryQuery on Repository {
        nameWithOwner
        viewerCanPush
        ...MilestoneFormRepositoryQueryInternal
      }
    `,
    props.repository,
  )

  const handleFormSubmit = useCallback(
    (input: CreateMilestoneInput, setIsSubmitting: Dispatch<SetStateAction<boolean>>) => {
      setSubmissionErrors(null)

      if (!repositoryData?.viewerCanPush) {
        setSubmissionErrors(LABELS.milestoneCreatePermissionError)
        setIsSubmitting(false)
        return
      }

      commitCreateRepositoryMilestoneMutation({
        environment,
        input,
        onError: (error: Error) => {
          setIsSubmitting(false)
          if (error.cause && Array.isArray(error.cause)) {
            setSubmissionErrors(formatFormErrorMessage(error.cause))
          } else {
            setSubmissionErrors(LABELS.milestoneCreateError)
          }
        },
        onCompleted: response => {
          if (!response.createMilestone?.milestone || response?.createMilestone?.errors?.length > 0) {
            setSubmissionErrors(LABELS.milestoneCreateError)
            setIsSubmitting(false)
            return
          }
          navigate(`/${repositoryData.nameWithOwner}/milestone/${response.createMilestone?.milestone.number}`)
        },
      })
    },
    [environment, navigate, repositoryData],
  )

  const handleFormCancel = () => {
    goBack()
  }

  const formDescription = (
    <p className={styles.milestonePageDescription}>
      {LABELS.createMilestoneDescription} {LABELS.learnMorePrefix}{' '}
      <Link href="https://docs.github.com/en/issues/tracking-your-work-with-issues/about-issues" inline>
        {LABELS.milestonesAndIssues}
      </Link>
      .
    </p>
  )

  return (
    <div className={styles.middlePaneWrapper} data-hpc data-testid="milestone-create">
      <ErrorBoundary
        fallback={<MilestoneError title={LABELS.milestonePageError} message={LABELS.milestonePageErrorMessage} />}
      >
        <MilestoneForm
          repository={repositoryData}
          optionConfig={props.optionConfig}
          formTitle={LABELS.createMilestone}
          formDescription={formDescription}
          formSubmitLabel={LABELS.createMilestone}
          onSubmit={handleFormSubmit}
          onCancel={handleFormCancel}
          submissionErrors={submissionErrors}
        />
      </ErrorBoundary>
    </div>
  )
}
