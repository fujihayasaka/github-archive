import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {SearchIcon} from '@primer/octicons-react'
import {Heading, PageLayout, TextInput} from '@primer/react'
import {Pagehead} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {useState} from 'react'

import {AssignmentDialog} from '../components/assignment-dialog/AssignmentDialog'
import {SecurityManagerTeamList} from '../components/team-list/SecurityManagerTeamList'
import styles from './EnterpriseSecurityManagers.module.css'

export interface EnterpriseSecurityManagersPayload {
  readonly: boolean
  canRemoveTeams: boolean
}

export function EnterpriseSecurityManagers(): JSX.Element {
  const payload = useRoutePayload<EnterpriseSecurityManagersPayload>()
  const [search, setSearch] = useState<string>('')

  const searchAndAddView = (
    <div className={styles.Box}>
      <TextInput
        data-testid="search-input"
        leadingVisual={SearchIcon}
        aria-label="Find a team search bar"
        name="search"
        value={search}
        onChange={e => setSearch(e.target.value)}
        placeholder="Find a team..."
        className={styles.TextInput}
      />
      {!payload.readonly && <AssignmentDialog />}
    </div>
  )

  return (
    <PageLayout className={styles.PageLayout}>
      <PageLayout.Header className={styles.PageLayout_Header}>
        <Pagehead className="pt-0 pb-2 mb-0">
          <Heading as="h2" data-testid="page-heading" className={clsx('f2', styles.Heading)}>
            Security managers
          </Heading>
        </Pagehead>
      </PageLayout.Header>
      <PageLayout.Content as="div">
        <div className="mb-3">
          <span className={styles.Text}>
            Grant a team permission to manage security alerts and settings across your organizations. The teams will
            also be granted read access to all repositories.{' '}
            {/* TODO: Uncomment this when the link is available
                <Link href="" inline>
                  Learn more about these security privileges.
                </Link>
              */}
          </span>
        </div>

        {searchAndAddView}

        <SecurityManagerTeamList search={search} hideRemoveAction={payload.readonly || !payload.canRemoveTeams} />
      </PageLayout.Content>
    </PageLayout>
  )
}
