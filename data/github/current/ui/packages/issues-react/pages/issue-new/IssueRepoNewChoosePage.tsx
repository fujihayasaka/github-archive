import {graphql, useFragment, usePreloadedQuery, type EntryPointComponent, type PreloadedQuery} from 'react-relay'
import {useNavigate} from '@github-ui/use-navigate'
import {useEntryPointsLoader} from '../../hooks/use-entrypoint-loaders'
import {AnalyticsWrapper} from '../AnalyticsWrapper'
import type {IssueRepoNewChoosePageQuery} from './__generated__/IssueRepoNewChoosePageQuery.graphql'

import {Box, Heading, Link} from '@primer/react'
import {LABELS} from '../../constants/labels'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {userHovercardPath} from '@github-ui/paths'
import styles from './IssueCreatePane.module.css'
import {useUser} from '@github-ui/use-user'

import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {DisplayMode} from '@github-ui/issue-create/DisplayMode'
import type {IssueRepoNewChoosePageContentInternal$key} from './__generated__/IssueRepoNewChoosePageContentInternal.graphql'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {TemplateListInternal} from '@github-ui/issue-create/TemplateListPane'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'

const PageQuery = graphql`
  query IssueRepoNewChoosePageQuery($name: String!, $owner: String!) {
    repository(owner: $owner, name: $name) {
      ...IssueRepoNewChoosePageContentInternal
    }
  }
`

export const IssueRepoNewChoosePage: EntryPointComponent<
  {
    pageQuery: IssueRepoNewChoosePageQuery
  },
  Record<string, never>
> = ({queries: {pageQuery}}) => {
  const {queryRef} = useEntryPointsLoader(pageQuery, PageQuery)

  if (!queryRef) return null

  return (
    <AnalyticsWrapper category="Repository Issue Create">
      <IssueRepoNewChoosePageContent pageQueryRef={queryRef} />
    </AnalyticsWrapper>
  )
}

export function IssueRepoNewChoosePageContent({
  pageQueryRef,
}: {
  pageQueryRef: PreloadedQuery<IssueRepoNewChoosePageQuery>
}) {
  const pageData = usePreloadedQuery<IssueRepoNewChoosePageQuery>(PageQuery, pageQueryRef)
  if (!pageData.repository) {
    reportError(
      new Error(`Could not find repository when loading TemplateList for ${ssrSafeLocation?.href.toString()}`),
    )
    return <div>Repository not found</div>
  }
  return <IssueRepoNewChoosePageContentInternal repository={pageData.repository} />
}

function IssueRepoNewChoosePageContentInternal({repository}: {repository: IssueRepoNewChoosePageContentInternal$key}) {
  const {currentUser} = useUser()
  const navigate = useNavigate()
  const data = useFragment(
    graphql`
      fragment IssueRepoNewChoosePageContentInternal on Repository {
        ...TemplateListPane
        name
        owner {
          login
        }
      }
    `,
    repository,
  )

  const safeConfig = getSafeConfig({
    defaultDisplayMode: DisplayMode.TemplatePicker,
    insidePortal: false,
    canBypassTemplateSelection: true,
    navigate,
    issueCreateArguments: {
      repository: {
        owner: data.owner.login,
        name: data.name,
      },
    },
  })

  if (!currentUser) {
    return <div>Current user not found</div>
  }
  const {avatarUrl, login} = currentUser

  return (
    <IssueCreateContextProvider optionConfig={safeConfig} preselectedData={undefined}>
      <div className={styles.createPane}>
        <Link href={`/${login}`} className={styles.avatarLink}>
          <span className="sr-only">{LABELS.viewProfile(login)}</span>
          <GitHubAvatar
            src={avatarUrl}
            size={32}
            alt={''}
            data-hovercard-url={userHovercardPath({owner: login})}
            className={styles.avatar}
          />
        </Link>
        <div className={styles.createPaneContainer} data-testid="issue-create-pane-container" data-hpc>
          <Heading as="h1" className={styles.header}>
            {LABELS.issueCreatePaneTitle}
          </Heading>
          <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 2}} tabIndex={-1} data-hpc>
            <TemplateListInternal repository={data} />
          </Box>
        </div>
      </div>
    </IssueCreateContextProvider>
  )
}
