import {useFragment, useRelayEnvironment, type PreloadedQuery} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {LabelRow$key} from './__generated__/LabelRow.graphql'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {ActionList, ConfirmationDialog, Link} from '@primer/react'
import {LabelToken} from '@github-ui/label-token'
import {ListItemDescriptionItem} from '@github-ui/list-view/ListItemDescriptionItem'
import styles from './RepositoryLabel.module.css'
import {type SafeHTMLString, SafeHTMLText} from '@github-ui/safe-html'
import {LABELS} from './constants/labels'
import {useCallback, useEffect, useRef, useState} from 'react'
import {commitDeleteLabelMutation} from './mutations/delete-label-mutation'
import {AriaAlert, Banner} from '@primer/react/experimental'
import {DialogForm as EditDialog} from './DialogForm'
import {formatFormErrorMessage} from './utils'
import {commitUpdateLabelMutation} from './mutations/update-label-mutation'
import type {IssuesAndPullRequestsCountSecondaryQuery} from './__generated__/IssuesAndPullRequestsCountSecondaryQuery.graphql'
import {IssuesAndPullRequestsCount} from './IssuesAndPullRequestsCount'
import {clsx} from 'clsx'

type LabelRowProps = {
  label: LabelRow$key
  isActionsAvailable: boolean
  viewerCanPush: boolean
  secondaryQueryRef?: PreloadedQuery<IssuesAndPullRequestsCountSecondaryQuery> | null
  repositoryId: string
  repositoryNameWithOwner: string
}

export function LabelRow({
  label,
  isActionsAvailable,
  viewerCanPush,
  secondaryQueryRef,
  repositoryId,
  repositoryNameWithOwner,
}: LabelRowProps) {
  const [errorsPresent, setErrorsPresent] = useState(false)
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editSubmissionErrors, setEditSubmissionErrors] = useState('')

  const errorBanner = useRef<HTMLDivElement>(null)

  const data = useFragment(
    graphql`
      fragment LabelRow on Label {
        id
        name
        nameHTML
        color
        description
      }
    `,
    label,
  )

  const environment = useRelayEnvironment()
  const handleDelete = useCallback(async () => {
    commitDeleteLabelMutation({
      environment,
      input: {id: data.id},
      onCompleted: () => {
        setErrorsPresent(false)
        setIsDialogOpen(false)

        // Upate the label counter in the header
        environment.commitUpdate(store => {
          const connectionId = `client:${repositoryId}:__LabelList_labels_connection(orderBy:{"direction":"ASC","field":"NAME"},skip:0)`
          const labelsConnection = store.get(connectionId)
          if (labelsConnection) {
            const totalCount = labelsConnection.getValue('totalCount') as number
            labelsConnection.setValue(Math.max(totalCount - 1, 0), 'totalCount')
          }
        })
      },
      onError: () => {
        setErrorsPresent(true)
      },
    })
  }, [data.id, repositoryId, environment])

  const handleEdit = useCallback(
    async (
      input: {
        name: string
        description: string
        color: string
      },
      setIsSubmitting: (isSubmitting: boolean) => void,
    ) => {
      setEditSubmissionErrors('')

      commitUpdateLabelMutation({
        environment,
        input: {
          id: data.id,
          name: input.name,
          description: input.description,
          color: input.color,
        },
        onCompleted: response => {
          if (!response.updateLabel?.label) {
            setEditSubmissionErrors(LABELS.editLabelError)
            setIsSubmitting(false)
            return
          }
          setIsSubmitting(false)
          setIsEditDialogOpen(false)
        },
        onError: (error: Error) => {
          if (error.cause && Array.isArray(error.cause)) {
            setEditSubmissionErrors(formatFormErrorMessage(error.cause))
          } else {
            setEditSubmissionErrors(LABELS.editLabelError)
          }
          setIsSubmitting(false)
        },
      })
    },
    [setEditSubmissionErrors, environment, data],
  )

  useEffect(() => {
    if (errorsPresent && errorBanner?.current) {
      errorBanner.current.focus()
    }
  }, [errorBanner, errorsPresent])

  return (
    <ListItem
      key={data.id}
      title={<></>} // We need to solve this. title is important for announcing the list item but we don't have a title concept here.
      role="listitem"
      secondaryActions={
        isActionsAvailable ? (
          <ListItemActionBar
            staticMenuActions={[
              ...(viewerCanPush
                ? [
                    {
                      key: 'edit',
                      render: () => <ActionList.Item onSelect={() => setIsEditDialogOpen(true)}>Edit</ActionList.Item>,
                    },
                  ]
                : []),
              ...(viewerCanPush
                ? [
                    {
                      key: 'delete',
                      render: () => (
                        <>
                          <ActionList.Divider />
                          <ActionList.Item variant="danger" onSelect={() => setIsDialogOpen(true)}>
                            {LABELS.deleteButtonText}
                          </ActionList.Item>
                        </>
                      ),
                    },
                  ]
                : []),
            ]}
          />
        ) : undefined
      }
    >
      <ListItemMainContent>
        <ListItemDescription className={clsx(styles.labelRowDescription, !isActionsAvailable && styles.noActionBar)}>
          <ListItemDescriptionItem>
            <Link href={`/${repositoryNameWithOwner}/labels/${encodeURIComponent(data.name)}`} muted>
              <LabelToken
                text={<SafeHTMLText html={data.nameHTML as SafeHTMLString} />}
                interactive
                key={0}
                fillColor={`#${data.color}`}
              />
            </Link>{' '}
          </ListItemDescriptionItem>
          <ListItemDescriptionItem className={styles.labelRowDescriptionItemDescription}>
            {data.description}
          </ListItemDescriptionItem>
          <IssuesAndPullRequestsCount
            repositoryNameWithOwner={repositoryNameWithOwner}
            labelName={data.name}
            labelId={data.id}
            secondaryQueryRef={secondaryQueryRef}
          />
        </ListItemDescription>
      </ListItemMainContent>
      {isDialogOpen && (
        <ConfirmationDialog
          onClose={gesture => {
            if (gesture === 'confirm') {
              handleDelete()
            } else {
              setErrorsPresent(false)
              setIsDialogOpen(false)
            }
          }}
          title={<p>{LABELS.labelDeleteDialogTitle}</p>}
          cancelButtonContent={LABELS.cancelButtonText}
          confirmButtonContent={LABELS.deleteLabelButtonText}
          confirmButtonType="danger"
        >
          <div>
            {errorsPresent && (
              <Banner
                ref={errorBanner}
                className="mb-3"
                title="Error"
                description={<AriaAlert>{LABELS.deleteLabelError}</AriaAlert>}
                variant="critical"
                role="alert"
              />
            )}
            <p>{LABELS.deleteLabelWarningPermanent}</p>
            <p>{LABELS.deleteLabelAssociatedIssuesNote}</p>
          </div>
        </ConfirmationDialog>
      )}
      {isEditDialogOpen && (
        <EditDialog
          onDialogClose={() => {
            setEditSubmissionErrors('')
            setIsEditDialogOpen(false)
          }}
          formTitle={LABELS.editLabel}
          descriptionPlaceholder={LABELS.labelDescriptionPlaceholder}
          submissionErrors={editSubmissionErrors}
          submitButtonText={LABELS.saveChanges}
          onDialogSubmit={handleEdit}
          initialValues={{
            name: data.name,
            description: data.description,
            color: data.color,
          }}
        />
      )}
    </ListItem>
  )
}
