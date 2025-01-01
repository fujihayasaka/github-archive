import {clsx} from 'clsx'
import {testIdProps} from '@github-ui/test-id-props'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Button, Heading} from '@primer/react'
import {useState} from 'react'
import {NewRoleAssignmentList} from './NewRoleAssignmentList'
import type {Role} from './NewRoleAssignmentListItem'
import styles from './NewRoleAssignmentPage.module.css'
import {NewRoleAssignmentAssigneeSelect, type Actor} from './NewRoleAssignmentAssigneeSelect'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'

export interface NewRoleAssignmentPageProps {
  roles: Role[]
  queryActorsPath: string
  submitAssignmentRoute: string
  cancelAction: () => void
}

export function NewRoleAssignmentPage(props: NewRoleAssignmentPageProps) {
  const {navigate, showBanner} = useBannerContext()
  const [assigneeType, setAssigneeType] = useState<'user' | 'businessteam' | 'team' | null>(null)
  const [assigneeId, setAssigneeId] = useState<number | null>(null)
  const [selectedRoleId, setSelectedRoleId] = useState<number | null>(null)
  const [submitting, setSubmitting] = useState(false)

  return (
    <div {...testIdProps('role-assignment-page')}>
      <div id="select-assignee-section" className={styles.pageSection}>
        <Heading className={styles.sectionTitle} as="h3">
          Assign role to
        </Heading>

        <NewRoleAssignmentAssigneeSelect
          assigneeId={assigneeId}
          assigneeType={assigneeType}
          queryActorsPath={props.queryActorsPath}
          onSelectCallback={handleActorSelect}
        />
      </div>

      <div id="select-role-section" className={styles.pageSection}>
        <Heading className={styles.sectionTitle} as="h3">
          Select role
        </Heading>
        <NewRoleAssignmentList
          roles={props.roles}
          selectedRoleId={selectedRoleId}
          onSelectCallback={handleRoleSelect}
        />
      </div>

      <div id="submit-assignment-section" className={clsx(styles.pageSection, styles.submitSection)}>
        <Button variant="primary" loading={submitting} onClick={handleSubmit}>
          Assign role
        </Button>
        <Button className={styles.cancelButton} disabled={submitting} onClick={props.cancelAction}>
          Cancel
        </Button>
      </div>
    </div>
  )

  function handleActorSelect(actor: Actor) {
    setAssigneeType(actor.type)
    setAssigneeId(actor.id)
  }

  function handleRoleSelect(roleId: number) {
    setSelectedRoleId(prevRoleAssigned => (prevRoleAssigned === roleId ? null : roleId))
  }

  async function handleSubmit() {
    setSubmitting(true)

    if (!assigneeType || !assigneeId || !selectedRoleId) {
      showBanner({message: 'Please select an actor and role to assign.', variant: 'warning'})
      setSubmitting(false)
      return
    }

    const result = await verifiedFetchJSON(props.submitAssignmentRoute, {
      method: 'POST',
      body: {role_id: selectedRoleId, assignee_type: assigneeType, assignee_id: assigneeId},
    })
    const json = await result.json()

    if (result.ok && json.success) {
      navigate(json.redirect_url, undefined, {message: json.message, variant: 'success'})
    } else {
      showBanner({
        message: json.error || 'Something went wrong while assigning the role. Please try again later.',
        variant: 'critical',
      })
      setSubmitting(false)
    }
  }
}
