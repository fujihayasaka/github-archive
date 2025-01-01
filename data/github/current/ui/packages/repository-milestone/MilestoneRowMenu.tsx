import {useFragment, useRelayEnvironment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {MilestoneRowMenu$key} from './__generated__/MilestoneRowMenu.graphql'
import {ActionList, ActionMenu, ConfirmationDialog} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import styles from './RepositoryMilestone.module.css'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {useCallback, useEffect, useRef, useState} from 'react'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {commitUpdateMilestoneMutation} from './mutations/update-milestone-mutation'
import {commitDeleteMilestoneMutation} from './mutations/delete-milestone-mutation'
import {LABELS} from './constants/labels'
import {AriaAlert, Banner} from '@primer/react/experimental'

type MilestoneRowMenuProps = {
  milestone: MilestoneRowMenu$key
}

export function MilestoneRowMenu({milestone}: MilestoneRowMenuProps) {
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [isProcessing, setIsProcessing] = useState(false)
  const [errorsPresent, setErrorsPresent] = useState(false)

  const errorBanner = useRef<HTMLDivElement>(null)

  const data = useFragment(
    graphql`
      fragment MilestoneRowMenu on Milestone {
        id
        state
        url
        repository {
          id
        }
      }
    `,
    milestone,
  )

  const navigate = useNavigate()
  const [searchParams] = useSearchParams()

  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const editCallback = useCallback(() => {
    const href = `${data.url.replace('/milestone/', '/milestones/')}/edit`
    const hrefParts = href.split('/')
    const milestoneIndex = hrefParts.lastIndexOf('milestone')
    if (milestoneIndex !== -1 && hrefParts[milestoneIndex + 1] === '') {
      hrefParts[milestoneIndex] = 'milestones'
    }
    const correctedHref = hrefParts.join('/')
    const url = new URL(correctedHref, window.location.origin)
    const path = url.pathname
    navigate(path)
  }, [data.url, navigate])

  const closeCallback = useCallback(() => {
    const lastState = data.state
    const newState = lastState === 'CLOSED' ? 'OPEN' : 'CLOSED'

    commitUpdateMilestoneMutation({
      environment,
      input: {id: data.id, state: newState},
      onCompleted: () => {
        // Update the counters in the store
        environment.commitUpdate(store => {
          const getOpenMilestones = store.get(`client:${data.repository.id}:milestones(first:0,states:"OPEN")`)
          if (getOpenMilestones) {
            const totalCount = getOpenMilestones.getValue('totalCount') as number
            getOpenMilestones.setValue(lastState === 'CLOSED' ? totalCount + 1 : totalCount - 1, 'totalCount')
          }
          const getClosedMilestones = store.get(`client:${data.repository.id}:milestones(first:0,states:"CLOSED")`)
          if (getClosedMilestones) {
            const totalCount = getClosedMilestones.getValue('totalCount') as number
            getClosedMilestones.setValue(lastState === 'CLOSED' ? totalCount - 1 : totalCount + 1, 'totalCount')
          }

          const searchString = searchParams.get('state')
          const state = searchString !== 'closed' ? 'OPEN' : 'CLOSED'

          const directionString = searchParams.get('direction')
          const direction = directionString === 'asc' ? 'ASC' : 'DESC'

          const orderString = searchParams.get('sort')
          let orderBy = 'CREATED_AT'
          if (orderString) {
            orderBy = orderString === 'due_date' ? 'DUE_DATE' : 'UPDATED_AT'
          }

          const connectionId = `client:${data.repository.id}:__MilestoneList_milestones_connection(orderBy:{"direction":"${direction}","field":"${orderBy}"},states:["${state}"])`
          const connectionRecord = store.get(connectionId)
          if (connectionRecord) {
            const edges = connectionRecord
              .getLinkedRecords('edges')
              ?.filter(edge => edge?.getLinkedRecord('node')?.getValue('id') !== data.id)
            connectionRecord.setLinkedRecords(edges || [], 'edges')
          }

          // Update the connection with the new state if needed
          const newConnectionId = `client:${data.repository.id}:__MilestoneList_milestones_connection(orderBy:{"direction":"${direction}","field":"${orderBy}"},states:["${newState}"])`
          const newConnectionRecord = store.get(newConnectionId)

          if (newConnectionRecord) {
            const edges = newConnectionRecord.getLinkedRecords('edges') || []
            const milestoneNode = store.get(data.id)
            if (milestoneNode) {
              const edgeId = `client:newEdge:${data.id}`
              let newEdge = store.get(edgeId)
              if (!newEdge) {
                newEdge = store.create(edgeId, 'MilestoneEdge')
              }
              newEdge.setLinkedRecord(milestoneNode, 'node')
              newConnectionRecord.setLinkedRecords([newEdge, ...edges], 'edges')
            }
          }
        })
      },
      onError: () => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Could not change Milestone state',
        })
      },
    })
  }, [addToast, data.id, data.repository.id, data.state, environment, searchParams])

  const deleteCallback = useCallback(() => {
    if (isProcessing) return

    setIsProcessing(true)

    commitDeleteMilestoneMutation({
      environment,
      input: {id: data.id},
      onCompleted: () => {
        // Update the counters in the store
        environment.commitUpdate(store => {
          const searchString = searchParams.get('state')
          const state = searchString !== 'closed' ? 'OPEN' : 'CLOSED'
          const getOpenMilestones = store.get(`client:${data.repository.id}:milestones(first:0,states:"OPEN")`)
          if (getOpenMilestones && state === 'OPEN') {
            const totalCount = getOpenMilestones.getValue('totalCount') as number
            getOpenMilestones.setValue(Math.max(totalCount - 1, 0), 'totalCount')
          }
          const getClosedMilestones = store.get(`client:${data.repository.id}:milestones(first:0,states:"CLOSED")`)
          if (getClosedMilestones && state === 'CLOSED') {
            const totalCount = getClosedMilestones.getValue('totalCount') as number
            getClosedMilestones.setValue(Math.max(totalCount - 1, 0), 'totalCount')
          }
        })
        setIsDeleteDialogOpen(false)
        setIsProcessing(false)
        setErrorsPresent(false)
      },
      onError: () => {
        setErrorsPresent(true)
        setIsProcessing(false)
      },
    })
  }, [data.id, data.repository.id, environment, searchParams, isProcessing])

  useEffect(() => {
    if (errorsPresent && errorBanner?.current) {
      errorBanner.current.focus()
    }
  }, [errorBanner, errorsPresent])

  return (
    <>
      <ActionMenu>
        <ActionMenu.Button
          className={styles.menuButton}
          aria-label="Milestone menu"
          variant="invisible"
          icon={<KebabHorizontalIcon />}
        />

        <ActionMenu.Overlay>
          <ActionList>
            <ActionList.Item onSelect={() => editCallback()}>Edit</ActionList.Item>
            <ActionList.Item onSelect={() => closeCallback()}>
              {data.state === 'CLOSED' ? 'Open' : 'Close'}
            </ActionList.Item>
            <ActionList.Divider />
            <ActionList.Item onSelect={() => setIsDeleteDialogOpen(true)}>
              <span className={styles.deleteMilestoneButton}>Delete</span>
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      {isDeleteDialogOpen && (
        <ConfirmationDialog
          onClose={gesture => {
            if (gesture === 'confirm') {
              deleteCallback()
            } else {
              setIsDeleteDialogOpen(false)
              setErrorsPresent(false)
            }
          }}
          title={<p className={styles.dialogTitle}>{LABELS.deleteMilestoneConfirmationTitle}</p>}
          cancelButtonContent={LABELS.cancel}
          confirmButtonContent={LABELS.deleteMilestoneConfirmationButton}
          confirmButtonType="danger"
        >
          <div className={styles.dialogDescriptionContainer}>
            {errorsPresent && (
              <Banner
                ref={errorBanner}
                className="mb-3"
                title="Error"
                description={<AriaAlert>{LABELS.deleteMilestoneError}</AriaAlert>}
                variant="critical"
                role="alert"
              />
            )}
            <p className={styles.dialogDescription}>{LABELS.deleteMilestoneWarningPermanent}</p>
            <p className={styles.dialogDescription}>{LABELS.deleteMilestoneAssociatedIssuesNote}</p>
          </div>
        </ConfirmationDialog>
      )}
    </>
  )
}
