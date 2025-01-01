import {clsx} from 'clsx'

import {useCallback, type RefObject, useState} from 'react'
import {Button, Heading} from '@primer/react'
import {GearIcon} from '@primer/octicons-react'

import {useUpdateAlertAssigneesMutation} from '../hooks/use-update-alert-assignees-mutation'
import type {Assignee, CodeScanningAssigneesRepository} from '../types'
import {AssigneePicker} from './AssigneePicker'
import {AssigneesList} from './AssigneesList'

import styles from './AssigneesSection.module.css'

export type AssigneesSectionProps = {
  repository: CodeScanningAssigneesRepository
  alertNumber: number
  currentUser: Assignee
  assignees: Assignee[]
  readonly: boolean
}

export function AssigneesSection({
  repository,
  alertNumber,
  currentUser,
  assignees: initialAssignees,
  readonly,
}: AssigneesSectionProps) {
  const maximumAssignees = 10

  const [assignees, setAssignees] = useState<Assignee[]>(initialAssignees)

  const {mutate: mutateUpdateAssignees, error: mutationError} = useUpdateAlertAssigneesMutation({
    owner: repository.ownerLogin,
    repo: repository.name,
    alertNumber,
  })

  const updateAssignees = useCallback(
    (selectedAssignees: Assignee[]) => {
      mutateUpdateAssignees(
        {
          assigneeIds: selectedAssignees.map(assignee => assignee.id),
        },
        {
          onSuccess: response => {
            setAssignees(response.assignees)
          },
        },
      )
    },
    [mutateUpdateAssignees],
  )

  return (
    <div className="d-flex flex-column flex-items-start pt-1 mb-3 position-relative width-full">
      <div className="width-full">
        {readonly ? (
          <div className="width-full position-relative pb-2">
            <Heading as="h3" className={clsx('top-1 f6 color-fg-muted position-relative', styles.sectionHeading)}>
              Assignees
            </Heading>
          </div>
        ) : (
          <AssigneePicker
            repository={repository}
            anchorElement={(props: React.HTMLAttributes<HTMLElement>, ref: RefObject<HTMLButtonElement>) => (
              <div className="width-full position-relative">
                <Heading as="h3" className={clsx('top-1 f6 color-fg-muted position-absolute', styles.sectionHeading)}>
                  Assignees
                </Heading>
                <Button
                  ref={ref}
                  {...props}
                  variant="invisible"
                  size="small"
                  trailingAction={GearIcon}
                  block
                  className="flex-content-start pl-0"
                >
                  <span className="sr-only f6 text-bold color-fg-muted lh-default">Edit assignees</span>
                </Button>
              </div>
            )}
            initialSelectedAssignees={assignees}
            currentUser={currentUser}
            maximumAssignees={maximumAssignees}
            onSelectionChange={(selectedAssignees: Assignee[]) => updateAssignees(selectedAssignees)}
            shortcutsEnabled={false}
            title={`Assign up to ${maximumAssignees} people to this alert`}
            mutationError={mutationError}
          />
        )}

        {assignees.length > 0 ? (
          <div className="width-full p-0">
            <AssigneesList assignees={assignees} />
          </div>
        ) : (
          <>
            <span className="f6 pr-2 mb-2 mt-1 color-fg-muted d-block">
              {readonly ? (
                <>No one assigned</>
              ) : (
                <>
                  No one -{' '}
                  <Button
                    variant="link"
                    onClick={() => updateAssignees([currentUser])}
                    className={clsx('color-fgAccent text-normal', styles.assignYourselfButton)}
                  >
                    Assign yourself
                  </Button>
                </>
              )}
            </span>
          </>
        )}
      </div>
    </div>
  )
}
