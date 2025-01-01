import {testIdProps} from '@github-ui/test-id-props'
import {CheckIcon, GlobeIcon, LockIcon, OrganizationIcon, StopIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Box, Button, Heading, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useEffect, useRef} from 'react'

import {Role} from '../../../../api/common-contracts'
import {getInitialState} from '../../../../helpers/initial-state'
import {fetchJSONIslandData} from '../../../../helpers/json-island'
import {toTitleCase} from '../../../../helpers/util'
import {
  useOrganizationAccessRole,
  useUpdateOrganizationAccessRoleOptimistically,
} from '../../../../queries/organization-access'
import {Link as RouterLink} from '../../../../router'
import {useProjectRouteParams} from '../../../../router/use-project-route-params'
import {PROJECT_SETTINGS_ROUTE} from '../../../../routes'
import {useProjectState} from '../../../../state-providers/memex/use-project-state'
import {ManageAccessResources} from '../../../../strings'
import {CollaboratorRoleDropDown, defaultCollaboratorRoleDropDownRoles} from './collaborator-role-drop-down'
import styles from './privacy-settings.module.css'

export const PrivacySettings: React.FC = () => {
  const {isPublicProject} = useProjectState()
  const {projectOwner, isOrganization} = getInitialState()
  const owner = projectOwner?.name?.toLowerCase()
  const {
    data: organizationAccessRole = Role.None,
    error,
    refetch: refetchOrganizationAccessRole,
    status: orgAccessRoleRequestStatus,
  } = useOrganizationAccessRole()
  const {mutate: updateOrganizationAccessRole, status: orgAccessRequestUpdateState} =
    useUpdateOrganizationAccessRoleOptimistically()

  const firstFocusElementRef = useRef<HTMLAnchorElement>(null)
  useEffect(() => {
    firstFocusElementRef.current?.focus()
  }, [])

  const projectRouteParams = useProjectRouteParams()
  return (
    <div className={styles.Box} {...testIdProps('privacy-settings')}>
      <Box
        sx={{
          mr: isOrganization ? 2 : 0,
        }}
        className={styles.Box_1}
        {...testIdProps('privacy-settings-manage-visibility')}
      >
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <Heading as="h2" className={styles.Heading}>
              {isPublicProject ? 'Public project' : 'Private project'}
            </Heading>
            <Octicon icon={isPublicProject ? GlobeIcon : LockIcon} className={styles.Octicon} />
          </div>
          <span className={styles.Octicon}>
            {isPublicProject
              ? 'This project is public and visible to anyone.'
              : 'Only those with access to this project can view it.'}
          </span>
        </div>
        <div>
          <Button
            ref={firstFocusElementRef}
            as={RouterLink}
            to={PROJECT_SETTINGS_ROUTE.generatePath(projectRouteParams)}
            {...testIdProps('privacy-settings-manage-access-link')}
          >
            Manage
          </Button>
        </div>
      </Box>
      {isOrganization && (
        <div className={styles.Box_1} {...testIdProps('privacy-settings-organization-access')}>
          <div className={styles.Box_2}>
            <div className={styles.Box_3}>
              <Heading as="h2" className={styles.Heading}>
                Base role
              </Heading>
              <Octicon icon={OrganizationIcon} className={styles.Octicon} />
            </div>
            <SelectedRoleText owner={owner} organizationAccessRole={organizationAccessRole} />
          </div>
          <div className={styles.Box_4}>
            {error ? (
              <Button disabled trailingVisual={TriangleDownIcon} {...testIdProps('collaborators-role-dropdown-button')}>
                {toTitleCase(organizationAccessRole)}
              </Button>
            ) : (
              <OrgAccessDropdown
                organizationAccessRole={organizationAccessRole}
                updateOrganizationAccessRole={updateOrganizationAccessRole}
              />
            )}
            <div aria-live="polite" {...testIdProps('org-access-update-status')}>
              <Status
                orgAccessRoleRequestStatus={orgAccessRoleRequestStatus}
                orgAccessRequestUpdateState={orgAccessRequestUpdateState}
                refetchOrganizationAccessRole={refetchOrganizationAccessRole}
              />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function SelectedRoleText({owner, organizationAccessRole}: {owner?: string; organizationAccessRole: Role}) {
  if (organizationAccessRole === Role.Admin) {
    return <span className={styles.Octicon}>{ManageAccessResources.privacySettingsAdmin}</span>
  }

  const base_url = fetchJSONIslandData('github-url')
  const ownerUrl = `${base_url}/orgs/${owner}/people?query=role%3Aowner`
  const ownerUrlTestId = 'privacy-settings-org-owners-link'

  if (organizationAccessRole === Role.Write) {
    return (
      <span className={styles.Octicon}>
        Everyone in the organization can see and edit this project.
        <Link
          inline
          rel="noopener noreferrer"
          target="_blank"
          href={ownerUrl}
          underline
          className={styles.Link}
          {...testIdProps(ownerUrlTestId)}
        >
          Owners
        </Link>
        are admins of this project.
      </span>
    )
  } else if (organizationAccessRole === Role.Read) {
    return (
      <span className={styles.Octicon}>
        Everyone in the organization can see this project.
        <Link
          inline
          rel="noopener noreferrer"
          target="_blank"
          href={ownerUrl}
          underline
          className={styles.Link}
          {...testIdProps(ownerUrlTestId)}
        >
          Owners
        </Link>
        are admins of this project.
      </span>
    )
  } else {
    return (
      <span className={styles.Octicon}>
        Only those with direct access and{' '}
        <Link
          inline
          rel="noopener noreferrer"
          target="_blank"
          href={ownerUrl}
          className={styles.Link_1}
          {...testIdProps(ownerUrlTestId)}
        >
          owners
        </Link>
        can see this project. Owners are also admins of this project.
      </span>
    )
  }
}

function Status({
  orgAccessRoleRequestStatus,
  orgAccessRequestUpdateState,
  refetchOrganizationAccessRole,
}: {
  orgAccessRoleRequestStatus: 'error' | 'success' | 'pending'
  orgAccessRequestUpdateState: 'error' | 'success' | 'pending' | 'idle'
  refetchOrganizationAccessRole: () => void
}) {
  if (orgAccessRequestUpdateState === 'error' || orgAccessRoleRequestStatus === 'error') {
    return (
      <div {...testIdProps('initial-org-access-request-failure-message')} className={styles.Box_5}>
        <Octicon icon={StopIcon} className={styles.Octicon_1} />
        <span>Something went wrong.</span>{' '}
        <Link as="button" onClick={() => refetchOrganizationAccessRole()}>
          Try again
        </Link>
      </div>
    )
  } else if (orgAccessRequestUpdateState === 'success') {
    return (
      <div {...testIdProps('org-access-request-success-message')} className={styles.Box_5}>
        <Octicon icon={CheckIcon} className={styles.Octicon_2} />
        <span>Changes saved</span>
      </div>
    )
  }
  return null
}

function OrgAccessDropdown({
  organizationAccessRole,
  updateOrganizationAccessRole,
}: {
  organizationAccessRole: Role
  updateOrganizationAccessRole: (args: {role: Role}) => void
}) {
  return (
    <CollaboratorRoleDropDown
      align="inside-left"
      roles={[
        ...defaultCollaboratorRoleDropDownRoles,
        {
          value: Role.None,
          displayName: toTitleCase(Role.None.toString()),
          description: ManageAccessResources.collaboratorDropDownNone,
        },
      ]}
      isOrganizationRole
      selectedRoles={[organizationAccessRole]}
      handleOnClick={role => {
        if (role === organizationAccessRole) return
        updateOrganizationAccessRole({role})
      }}
    />
  )
}
