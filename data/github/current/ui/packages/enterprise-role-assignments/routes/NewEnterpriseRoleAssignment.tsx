import {enterpriseRoleAssignmentsPath, newEnterpriseRoleAssignmentQueryActorsPath} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Breadcrumbs, PageHeader} from '@primer/react'
import styles from './NewEnterpriseRoleAssignment.module.css'
import {NewRoleAssignmentPage} from '../components/NewRoleAssignmentPage'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import type {NewEnterpriseRoleAssignmentPayload} from '../enterprise-role-assignments-types'

export function NewEnterpriseRoleAssignment() {
  const payload = useRoutePayload<NewEnterpriseRoleAssignmentPayload>()
  const {navigate} = useBannerContext()

  return (
    <div>
      <PageHeader>
        <PageHeader.ContextArea hidden={false}>
          <PageHeader.ContextBar hidden={false}>
            <Breadcrumbs>
              <Breadcrumbs.Item href={enterpriseRoleAssignmentsPath({slug: payload.slug})}>
                Role assignments
              </Breadcrumbs.Item>
              <Breadcrumbs.Item selected>Assign role</Breadcrumbs.Item>
            </Breadcrumbs>
          </PageHeader.ContextBar>
        </PageHeader.ContextArea>
        <PageHeader.TitleArea className={styles.title}>
          <PageHeader.Title as="h1">Assign role</PageHeader.Title>
        </PageHeader.TitleArea>
        <PageHeader.Description className={styles.description}>
          Grant an enterprise role to a user or enterprise team in {payload.enterpriseName}
        </PageHeader.Description>
      </PageHeader>

      <NewRoleAssignmentPage
        roles={payload.roles}
        enterpriseOrgs={payload.enterpriseOrgs}
        enterpriseTeamOrgAssignmentLimitExceeded={payload.enterpriseTeamOrgAssignmentLimitExceeded}
        queryActorsPath={newEnterpriseRoleAssignmentQueryActorsPath({slug: payload.slug})}
        submitAssignmentRoute={enterpriseRoleAssignmentsPath({slug: payload.slug})}
        cancelAction={() => {
          navigate(`/enterprises/${payload.slug}/enterprise_role_assignments`)
        }}
      />
    </div>
  )
}
