import {useEffect, useRef, useState} from 'react'
import {Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {Title} from '../components/Title'
import {Resources} from '../constants/strings'
import {type EntryPointComponent, type PreloadedQuery, graphql, usePreloadedQuery} from 'react-relay'
import type {OrganizationIssueTypesSettingsQuery} from './__generated__/OrganizationIssueTypesSettingsQuery.graphql'
import {OrganizationIssueTypesList} from '../components/OrganizationIssueTypesList'
import styles from './OrganizationIssueTypesSettings.module.css'
import {ORGANIZATION_ISSUE_TYPES_LIMIT} from '../constants/constants'
import {AriaAlert, Banner} from '@primer/react/experimental'
import {useIssueTypesMutationErrorsContext} from '../contexts/IssueTypesMutationErrorsContext'

export const organizationIssueTypes = graphql`
  query OrganizationIssueTypesSettingsQuery($organization_id: String!, $pageSize: Int!) {
    organization(login: $organization_id) {
      login
      ...OrganizationIssueTypesList @arguments(issueTypesListPageSize: $pageSize)
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

  const {mutationError} = useIssueTypesMutationErrorsContext()

  const errorBanner = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!!mutationError && errorBanner?.current) {
      errorBanner.current.focus()
    }
  }, [mutationError])

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
            id="create-issue-type"
          >
            {Resources.createButton}
          </Button>
        )}
      </div>

      {!!mutationError && (
        <Banner
          className={styles.errorBanner}
          ref={errorBanner}
          title={Resources.errorTitle}
          description={<AriaAlert>{mutationError}</AriaAlert>}
          variant="critical"
          role="alert"
        />
      )}

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
        <Dialog.Header id="header-id">
          {Resources.limitReachedDialogTitle(ORGANIZATION_ISSUE_TYPES_LIMIT)}
        </Dialog.Header>
        <Box sx={{p: 3}}>
          <span>{Resources.limitReachedDialogBody}</span>
        </Box>
      </Dialog>
    </form>
  )
}
