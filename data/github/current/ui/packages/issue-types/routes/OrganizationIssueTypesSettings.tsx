import {useRef, useState} from 'react'
import {Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {Title} from '../components/Title'
import {Resources} from '../constants/strings'
import {type EntryPointComponent, type PreloadedQuery, graphql, usePreloadedQuery} from 'react-relay'
import type {OrganizationIssueTypesSettingsQuery} from './__generated__/OrganizationIssueTypesSettingsQuery.graphql'
import {OrganizationIssueTypesList} from '../components/OrganizationIssueTypesList'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import FeedbackLink from '../components/FeedbackLink'
import styles from './OrganizationIssueTypesSettings.module.css'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export const organizationIssueTypes = graphql`
  query OrganizationIssueTypesSettingsQuery($organization_id: String!) {
    organization(login: $organization_id) {
      login
      ...OrganizationIssueTypesList @arguments(issueTypesListPageSize: 10)
    }
  }
`

export type PreloadedQueries = {
  organizationIssueTypesSettingsQuery: PreloadedQuery<OrganizationIssueTypesSettingsQuery>
}

export const OrganizationIssueTypesSettings: EntryPointComponent<
  {organizationIssueTypesSettingsQuery: OrganizationIssueTypesSettingsQuery},
  Record<string, never>
> = ({queries: {organizationIssueTypesSettingsQuery}}) => {
  const preloadedData = usePreloadedQuery<OrganizationIssueTypesSettingsQuery>(
    organizationIssueTypes,
    organizationIssueTypesSettingsQuery,
  )
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  const returnFocusRef = useRef(null)
  const [isIssueTypesLimitReached, setIsIssueTypesLimitReached] = useState<boolean>(false)
  const [isDialogOpen, setIsDialogOpen] = useState<boolean>(false)

  if (!preloadedData?.organization) return null

  return (
    // a11y feedback: it's a form because it has form controls and it represents a UI that alters some state on the server.
    // Not having a single "submit" button does not preclude it from being a form.
    // We prevent default to prevent reloading the page on every toggle or menu opening
    <form aria-labelledby="issue-types-heading" onSubmit={e => e.preventDefault()}>
      <div className={styles.titleContainer}>
        <Title showBorder={false} sx={{flex: 1}}>
          {Resources.settingsPageHeader}
        </Title>
        {enabled ? <BetaLabel feedbackUrl="https://gh.io/issue-types-feedback" /> : <FeedbackLink />}
      </div>
      <div className={styles.infoArea}>
        <p className={styles.infoBlockTextOrg}>{Resources.infoBlockTextOrg}</p>
        {isIssueTypesLimitReached ? (
          <Button variant="primary" ref={returnFocusRef} onClick={() => setIsDialogOpen(true)}>
            {Resources.createButton}
          </Button>
        ) : (
          <Button
            as="a"
            href={`/organizations/${preloadedData.organization.login}/settings/issue-types/new`}
            variant="primary"
          >
            {Resources.createButton}
          </Button>
        )}
      </div>
      <OrganizationIssueTypesList
        node={preloadedData.organization}
        aria-label={Resources.ariaLabel.issueTypeList}
        setIsIssueTypesLimitReached={setIsIssueTypesLimitReached}
      />

      <Dialog
        returnFocusRef={returnFocusRef}
        isOpen={isDialogOpen}
        onDismiss={() => setIsDialogOpen(false)}
        aria-labelledby="header-id"
      >
        <Dialog.Header id="header-id">{Resources.limitReachedDialogTitle}</Dialog.Header>
        <Box sx={{p: 3}}>
          <span>{Resources.limitReachedDialogBody}</span>
        </Box>
      </Dialog>
    </form>
  )
}
