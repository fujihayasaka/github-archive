import {LABELS} from './constants/labels'
import {DialogForm as CreateDialog} from './DialogForm'
import {ConnectionHandler, graphql, useFragment, useRelayEnvironment} from 'react-relay'
import type {LabelCreate$key} from './__generated__/LabelCreate.graphql'
import {commitCreateRepositoryLabelMutation} from './mutations/create-repository-label-mutation'
import {formatFormErrorMessage} from './utils/format-form-error-message'
import {useCallback, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import type {createRepositoryLabelMutation$data} from './mutations/__generated__/createRepositoryLabelMutation.graphql'
import type {OrderDirection} from './__generated__/LabelListQuery.graphql'
import {SORT_MAP, VALID_UI_SORT_DIRECTIONS, type SortKeyword} from './sort-options'

type LabelCreateProps = {
  repository: LabelCreate$key
  isOpen: boolean
  onClose: () => void
}

function getConnectionVars(sp: URLSearchParams) {
  const sortParam = sp.get('sort') ?? 'name-asc'
  const [sortKey, direction = 'asc'] = sortParam.split('-') as [string, 'asc' | 'desc' | undefined]

  const orderField = SORT_MAP[sortKey as SortKeyword] ?? SORT_MAP.name
  const orderDirection = VALID_UI_SORT_DIRECTIONS.includes(direction) ? direction : 'asc'

  return {
    orderBy: {
      direction: orderDirection.toUpperCase() as OrderDirection,
      field: orderField,
    },
    skip: 0,
    ...(sp.get('q') && {query: sp.get('q')}),
  }
}

export function LabelCreate({repository, isOpen, onClose}: LabelCreateProps) {
  const environment = useRelayEnvironment()
  const [submissionErrors, setSubmissionErrors] = useState('')
  const [searchParams] = useSearchParams()

  const repositoryData = useFragment(
    graphql`
      fragment LabelCreate on Repository {
        id
        viewerCanPush
      }
    `,
    isOpen ? repository : null,
  )

  const handleSubmit = useCallback(
    (input: {name: string; description: string; color: string}, setIsSubmitting: (isSubmitting: boolean) => void) => {
      setSubmissionErrors('')

      if (!repositoryData?.viewerCanPush) {
        setSubmissionErrors(LABELS.labelCreatePermissionError)
        setIsSubmitting(false)
        return
      }

      const connectionVars = getConnectionVars(searchParams)
      const connectionId = ConnectionHandler.getConnectionID(repositoryData.id, 'LabelList_labels', connectionVars)

      commitCreateRepositoryLabelMutation({
        environment,
        input: {
          repositoryId: repositoryData.id,
          name: input.name,
          color: input.color,
          description: input.description,
        },
        connectionId,
        onError: (error: Error) => {
          setIsSubmitting(false)
          if (error.cause && Array.isArray(error.cause)) {
            setSubmissionErrors(formatFormErrorMessage(error.cause))
          } else {
            setSubmissionErrors(LABELS.labelCreateError)
          }
        },
        onCompleted: (response: createRepositoryLabelMutation$data) => {
          setIsSubmitting(false)
          if (response.createLabel?.errors && response.createLabel.errors.length > 0) {
            setSubmissionErrors(formatFormErrorMessage(response.createLabel.errors))
          } else {
            onClose()
          }
        },
      })
    },
    [environment, repositoryData, onClose, searchParams],
  )

  const handleClose = useCallback(() => {
    setSubmissionErrors('')
    onClose()
  }, [onClose])

  if (!isOpen) {
    return null
  }

  return (
    <CreateDialog
      onDialogClose={handleClose}
      formTitle={LABELS.newLabel}
      namePlaceholder={LABELS.labelNamePlaceholder}
      descriptionPlaceholder={LABELS.labelDescriptionPlaceholder}
      submissionErrors={submissionErrors}
      submitButtonText={LABELS.createButtonText}
      onDialogSubmit={handleSubmit}
    />
  )
}
