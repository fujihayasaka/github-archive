import {clsx} from 'clsx'
import {testIdProps} from '@github-ui/test-id-props'
import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Button, Heading} from '@primer/react'
import {useState} from 'react'
import {NewRoleAssignmentList} from './NewRoleAssignmentList'
import styles from './NewRoleAssignmentPage.module.css'
import {NewRoleAssignmentAssigneeSelect, type Actor} from './NewRoleAssignmentAssigneeSelect'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import type {AssigneeType, EnterpriseOrg, Role} from '../enterprise-role-assignments-types'
import {esmStatus, isEsm} from '../utils/role-utils'

export interface NewRoleAssignmentPageProps {
  roles: Role[]
  queryActorsPath: string
  submitAssignmentRoute: string
  enterpriseOrgs?: EnterpriseOrg[]
  enterpriseTeamOrgAssignmentLimitExceeded?: boolean
  cancelAction: () => void
}

type Result =
  | {
      error: string
      success?: false
    }
  | {
      success: true
      message: string
      redirect_url: string
    }

export function NewRoleAssignmentPage({
  roles,
  submitAssignmentRoute,
  queryActorsPath,
  cancelAction,
  enterpriseOrgs,
  enterpriseTeamOrgAssignmentLimitExceeded,
}: NewRoleAssignmentPageProps) {
  const {navigate, showBanner} = useBannerContext()
  const [assigneeType, setAssigneeType] = useState<AssigneeType | null>(null)
  const [assigneeId, setAssigneeId] = useState<number | null>(null)
  const [selectedRoleId, setSelectedRoleId] = useState<number | null>(null)
  const selectedRole = roles?.find(role => role.id === selectedRoleId)

  function handleActorSelect(actor: Actor) {
    if (
      selectedRole &&
      isEsm(selectedRole) &&
      esmStatus(actor.type, !!enterpriseTeamOrgAssignmentLimitExceeded).status === 'disabled'
    ) {
      setSelectedRoleId(null)
    }
    setAssigneeType(actor.type)
    setAssigneeId(actor.id)
  }

  const {mutate, isPending} = useMutation<Result>({
    mutationFn: async () => {
      const response = await verifiedFetchJSON(submitAssignmentRoute, {
        method: 'POST',
        body: {role_id: selectedRoleId, assignee_type: assigneeType, assignee_id: assigneeId},
      })

      // Potential expected errors, handled in onSuccess callback
      if (response.ok || response.status === 403 || response.status === 422) {
        const result = await response.json()
        if ('error' in result || 'success' in result) {
          return result
        }
        throw new Error('Unexpected JSON structure in response')
      }

      throw new Error(response.statusText)
    },
    onError: () => {
      showBanner({
        message: 'Something went wrong while assigning the role. Please try again later.',
        variant: 'critical',
      })
    },
    onSuccess: data => {
      if (data.success) {
        navigate(data.redirect_url, undefined, {
          message: data.message,
          variant: 'success',
        })
      } else {
        showBanner({
          message: data.error,
          variant: 'critical',
        })
      }
    },
  })

  return (
    <div {...testIdProps('role-assignment-page')}>
      <div id="select-assignee-section" className={styles.pageSection}>
        <Heading className={styles.sectionTitle} as="h3">
          Assign role to
        </Heading>

        <NewRoleAssignmentAssigneeSelect
          assigneeId={assigneeId}
          assigneeType={assigneeType}
          queryActorsPath={queryActorsPath}
          onSelectCallback={handleActorSelect}
        />
      </div>

      <div id="select-role-section" className={styles.pageSection}>
        <Heading className={styles.sectionTitle} as="h3">
          Select role
        </Heading>
        <NewRoleAssignmentList
          roles={roles}
          enterpriseOrgs={enterpriseOrgs}
          assigneeType={assigneeType}
          selectedRoleId={selectedRoleId}
          onSelectCallback={handleRoleSelect}
        />
      </div>

      <div id="submit-assignment-section" className={clsx(styles.pageSection, styles.submitSection)}>
        <Button variant="primary" loading={isPending} onClick={handleSubmit}>
          Assign role
        </Button>
        <Button className={styles.cancelButton} disabled={isPending} onClick={cancelAction}>
          Cancel
        </Button>
      </div>
    </div>
  )

  function handleRoleSelect(roleId: number) {
    setSelectedRoleId(prevRoleAssigned => (prevRoleAssigned === roleId ? null : roleId))
  }

  function handleSubmit() {
    if (!assigneeType || !assigneeId || !selectedRoleId) {
      showBanner({message: 'Please select an actor and role to assign.', variant: 'warning'})
      return
    }
    mutate()
  }
}
