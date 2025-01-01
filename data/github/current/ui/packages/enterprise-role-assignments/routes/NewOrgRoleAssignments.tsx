import {orgRoleAssignmentsPath, newOrgRoleAssignmentQueryActorsPath} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import {Breadcrumbs, Link, PageHeader} from '@primer/react'
import styles from './OrgRoleAssignments.module.css'
import {NewRoleAssignmentPage} from '../components/NewRoleAssignmentPage'
import type {Role} from '../components/NewRoleAssignmentListItem'

export interface NewOrgRoleAssignmentPayload {
  slug: string
  roles: Role[]
}

export function NewOrgRoleAssignment() {
  const payload = useRoutePayload<NewOrgRoleAssignmentPayload>()
  const {navigate} = useBannerContext()

  return (
    <>
      <PageHeader>
        <PageHeader.ContextArea hidden={false}>
          <PageHeader.ContextBar hidden={false}>
            <Breadcrumbs>
              <Breadcrumbs.Item href={orgRoleAssignmentsPath({slug: payload.slug})}>Role assignments</Breadcrumbs.Item>
              <Breadcrumbs.Item selected>Assign role</Breadcrumbs.Item>
            </Breadcrumbs>
          </PageHeader.ContextBar>
        </PageHeader.ContextArea>
        <PageHeader.TitleArea className="pb-1">
          <PageHeader.Title as="h2">Assign role</PageHeader.Title>
        </PageHeader.TitleArea>
        <PageHeader.Description className={styles.description}>
          <div>
            Organization roles are used to grant access to subsets of organization settings to teams and members.{' '}
            <Link
              inline
              href="https://docs.github.com/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization"
            >
              Learn more about organization roles.
            </Link>
          </div>
        </PageHeader.Description>
      </PageHeader>

      <NewRoleAssignmentPage
        roles={payload.roles}
        queryActorsPath={newOrgRoleAssignmentQueryActorsPath({slug: payload.slug})}
        submitAssignmentRoute={orgRoleAssignmentsPath({slug: payload.slug})}
        cancelAction={() => {
          navigate(`/organizations/${payload.slug}/settings/org_role_assignments`)
        }}
      />
    </>
  )
}
