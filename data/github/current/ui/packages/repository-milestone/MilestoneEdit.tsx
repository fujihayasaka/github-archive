import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'

import styles from './MilestoneCreateEdit.module.css'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {MilestoneError} from './MilestoneError'
import {LABELS} from './constants/labels'
import {MilestoneForm, type MilestoneInitialValues} from './components/MilestoneForm'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'
import {goBack} from '@github-ui/history'
import {useCallback, useState, type Dispatch, type SetStateAction} from 'react'
import type {MilestoneEditFormRepositoryQuery$key} from './__generated__/MilestoneEditFormRepositoryQuery.graphql'
import type {CreateMilestoneInput} from './mutations/__generated__/createRepositoryMilestoneMutation.graphql'
import {commitUpdateMilestoneMutation} from './mutations/update-milestone-mutation'
import {formatFormErrorMessage} from './utils/format-form-error-message'
import {useNavigate} from '@github-ui/use-navigate'
import {commitUpdateMilestoneDetailsMutation} from './mutations/update-milestone-details-mutation'

type EditMilestoneInput = {
  id: string
  title: string
  description?: string | null
  dueOn?: string | null
}

type MilestoneEditProps = {
  repository: MilestoneEditFormRepositoryQuery$key
  optionConfig?: UserSettingsOptionConfig
}

export function MilestoneEdit(props: MilestoneEditProps) {
  const [submissionErrors, setSubmissionErrors] = useState<string | null>(null)
  const navigate = useNavigate()
  const environment = useRelayEnvironment()

  const {repository} = props

  const repositoryData = useFragment(
    graphql`
      fragment MilestoneEditFormRepositoryQuery on Repository @argumentDefinitions(number: {type: "Int!"}) {
        nameWithOwner
        viewerCanPush
        milestone(number: $number) {
          id
          number
          title
          description
          dueOn
          state
        }
        ...MilestoneFormRepositoryQueryInternal
      }
    `,
    repository,
  )

  const handleFormSubmit = useCallback(
    (input: CreateMilestoneInput, setIsSubmitting: Dispatch<SetStateAction<boolean>>) => {
      setSubmissionErrors(null)

      if (!repositoryData.milestone) {
        setSubmissionErrors(LABELS.milestoneErrorMessage)
        setIsSubmitting(false)
        return
      }

      if (!repositoryData?.viewerCanPush) {
        setSubmissionErrors(LABELS.milestoneEditPermissionError)
        setIsSubmitting(false)
        return
      }

      const editingInput: EditMilestoneInput = {
        id: repositoryData.milestone.id,
        title: input.title,
        description: input.description,
        dueOn: input.dueOn,
      }

      commitUpdateMilestoneDetailsMutation({
        environment,
        input: editingInput,
        onError: (error: Error) => {
          setIsSubmitting(false)
          if (error.cause && Array.isArray(error.cause)) {
            setSubmissionErrors(formatFormErrorMessage(error.cause))
          } else {
            setSubmissionErrors(LABELS.milestoneEditError)
          }
        },
        onCompleted: response => {
          if (!response.updateMilestone?.milestone || response?.updateMilestone?.errors?.length > 0) {
            setSubmissionErrors(LABELS.milestoneEditError)
            setIsSubmitting(false)
            return
          }

          if (repositoryData.milestone) {
            navigate(`/${repositoryData.nameWithOwner}/milestone/${repositoryData.milestone.number}`)
          }
        },
      })
    },
    [environment, navigate, repositoryData],
  )

  const handleToggleMilestoneState = useCallback(
    (e: React.MouseEvent, setIsSubmitting: Dispatch<SetStateAction<boolean>>) => {
      e.preventDefault()
      setIsSubmitting(true)
      setSubmissionErrors(null)

      if (!repositoryData?.milestone) {
        setSubmissionErrors(LABELS.milestoneErrorMessage)
        setIsSubmitting(false)
        return
      }

      if (!repositoryData?.viewerCanPush) {
        setSubmissionErrors(LABELS.milestoneEditPermissionError)
        setIsSubmitting(false)
        return
      }

      const prevState = repositoryData?.milestone?.state

      commitUpdateMilestoneMutation({
        environment,
        input: {
          id: repositoryData.milestone.id,
          state: prevState === 'CLOSED' ? 'OPEN' : 'CLOSED',
        },
        onError: (error: Error) => {
          setIsSubmitting(false)
          if (error.cause && Array.isArray(error.cause)) {
            setSubmissionErrors(formatFormErrorMessage(error.cause))
          } else {
            setSubmissionErrors(LABELS.milestoneEditError)
          }
        },
        onCompleted: response => {
          if (!response.updateMilestone?.milestone) {
            setSubmissionErrors(LABELS.milestoneEditError)
            setIsSubmitting(false)
            return
          }

          navigate(`/${repositoryData.nameWithOwner}/milestone/${repositoryData?.milestone?.number}`)
        },
      })
    },
    [environment, navigate, repositoryData],
  )

  if (!repositoryData?.milestone) {
    return (
      <div className={styles.middlePaneWrapper}>
        <MilestoneError title={LABELS.milestoneError} message={LABELS.milestoneErrorMessage} />
      </div>
    )
  }

  const initialValues: MilestoneInitialValues = {
    id: repositoryData.milestone.id,
    title: repositoryData.milestone.title,
    description: repositoryData.milestone.description,
    dueOn: repositoryData.milestone.dueOn,
  }

  const handleFormCancel = () => {
    goBack()
  }

  return (
    <div className={styles.middlePaneWrapper} data-testid="milestone-edit">
      <ErrorBoundary
        fallback={<MilestoneError title={LABELS.milestonePageError} message={LABELS.milestonePageErrorMessage} />}
      >
        <MilestoneForm
          repository={repositoryData}
          optionConfig={props.optionConfig}
          formTitle={LABELS.editMilestoneTitle}
          formSubmitLabel={LABELS.saveChanges}
          onSubmit={handleFormSubmit}
          onCancel={handleFormCancel}
          submissionErrors={submissionErrors}
          initialValues={initialValues}
          onToggleMilestoneState={handleToggleMilestoneState}
          toggleStateLabel={repositoryData.milestone.state === 'OPEN' ? LABELS.closeMilestone : LABELS.reopenMilestone}
        />
      </ErrorBoundary>
    </div>
  )
}
