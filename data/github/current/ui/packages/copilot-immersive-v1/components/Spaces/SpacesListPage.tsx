import ServiceView from '@github-ui/copilot-chat/components/Service/ServiceView'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {COPILOT_SPACES_NEW_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CustomCopilotId, IndexCustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useDeleteCustomCopilot} from '@github-ui/custom-copilots/hooks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {Link} from '@github-ui/react-core/link'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {useSearchParams} from '@github-ui/use-navigate'
import {AlertIcon, OrganizationIcon, SearchIcon, SmileyIcon, StarIcon} from '@primer/octicons-react'
import {Button, Flash, UnderlineNav} from '@primer/react'
import {useState} from 'react'
import {useNavigate} from 'react-router-dom'

import {ErrorFallback} from '../ErrorFallback'
import SpacesIcon from '../Icons/SpacesIcon'
import {SpacesCard} from './SpacesCard'
import {SpacesHeader} from './SpacesHeader'
import styles from './SpacesListPage.module.css'

const title = 'Set context once. Chat again and again'
const description =
  'Create and share a custom Copilot experience using a collection of GitHub repositories, files, and other content.'

const tabTypes = ['personal', 'org', 'starred'] as const
type TabType = (typeof tabTypes)[number]
export interface SpacesViewProps {
  copilotSpaces: IndexCustomCopilot[] | undefined
}

export function SpacesListPage({copilotSpaces}: SpacesViewProps) {
  const spaceVisibilityEnabled = copilotFeatureFlags.customCopilotVisibility

  const state = useChatState()
  const navigate = useNavigate()
  const {ssoOrganizations} = state
  const [searchParams] = useSearchParams()

  let activeTab: TabType
  const tabParam = searchParams.get('tab')
  if (tabTypes.includes(tabParam as TabType)) {
    activeTab = tabParam as TabType
  } else {
    activeTab = 'personal'
  }

  const allProtectedOrgs = ssoOrganizations.map(org => org.login)

  const [deletionError, setDeletionError] = useState<Error | null>(null)
  const isLoading = copilotSpaces === undefined
  const personalSpacesCount = copilotSpaces?.filter(space => !space.ownerIsOrg).length ?? 0
  const orgSpacesCount = copilotSpaces?.filter(space => space.ownerIsOrg).length ?? 0
  const starredSpacesCount = copilotSpaces?.filter(space => space.starred).length ?? 0

  const handleCreate = () => {
    navigate(COPILOT_SPACES_NEW_PATH)
  }

  const {mutateAsync: deleteCustomCopilot} = useDeleteCustomCopilot()

  const handleCopilotSpaceDelete = (item: CustomCopilotId) => async () => {
    try {
      await deleteCustomCopilot(item)
      setDeletionError(null)
    } catch (err) {
      setDeletionError(err instanceof Error ? err : new Error(String(err)))
    }
  }

  const handleOnClickCopilotSpace = () => {
    sendEvent('dotcom_chat.activate', {
      target: 'SIDEBAR_CUSTOM_COPILOT_SELECTED',
      mode: 'immersive',
    })
  }

  const filteredSpaces = copilotSpaces?.filter(space => {
    if (activeTab === 'personal') return !space.ownerIsOrg
    if (activeTab === 'org') return space.ownerIsOrg
    if (activeTab === 'starred') return space.starred
    return true
  })

  const hasNoSpaces = copilotSpaces?.length === 0 && !isLoading
  const hasNoMatchingSpaces = copilotSpaces && copilotSpaces.length > 0 && filteredSpaces?.length === 0 && !isLoading

  const getCategoryName = () => {
    if (activeTab === 'personal') return 'personal'
    if (activeTab === 'org') return 'organization'
    if (activeTab === 'starred') return 'starred'
    return ''
  }

  return (
    <ErrorBoundary fallback={<ErrorFallback regionName="Spaces" />}>
      <SpacesHeader onCreateSpace={handleCreate} />
      {deletionError && (
        <Flash variant="danger">
          <AlertIcon />
          There was a problem deleting your space.
        </Flash>
      )}
      <ServiceView.Container>
        <ServiceView.Banner>
          {ssoOrganizations.length > 0 && (
            <div className={styles.banner}>
              <SingleSignOnBanner
                protectedOrgs={allProtectedOrgs}
                redirectURI={() =>
                  `/search/refresh_blackbird_caches?return_to=${encodeURIComponent(window.location.href)}`
                }
                useFullWidthStyle
              />
            </div>
          )}
        </ServiceView.Banner>
        <ServiceView.Header>
          <ServiceView.Icon icon={<SpacesIcon size={32} />} />
          <ServiceView.Title>{title}</ServiceView.Title>
          <ServiceView.Description>{description}</ServiceView.Description>
        </ServiceView.Header>

        <div className={styles.listContainer}>
          <div className={styles.underlineNav}>
            <UnderlineNav aria-label="Spaces">
              <UnderlineNav.Item
                as={Link}
                to={{search: '?tab=personal'}}
                aria-current={activeTab === 'personal' ? 'page' : undefined}
                icon={SmileyIcon}
                counter={personalSpacesCount}
              >
                Yours
              </UnderlineNav.Item>
              <UnderlineNav.Item
                as={Link}
                to={{search: '?tab=org'}}
                aria-current={activeTab === 'org' ? 'page' : undefined}
                icon={OrganizationIcon}
                counter={orgSpacesCount}
              >
                Organizations
              </UnderlineNav.Item>
              <UnderlineNav.Item
                as={Link}
                to={{search: '?tab=starred'}}
                aria-current={activeTab === 'starred' ? 'page' : undefined}
                icon={StarIcon}
                counter={starredSpacesCount}
              >
                Starred
              </UnderlineNav.Item>
            </UnderlineNav>
          </div>

          <ServiceView.Section>
            <ServiceView.Section.Grid loading={isLoading}>
              {hasNoSpaces ? (
                <ServiceView.Section.Grid.Empty>
                  <p>Spaces you create will appear here.</p>
                  <Button onClick={handleCreate}>New space</Button>
                </ServiceView.Section.Grid.Empty>
              ) : hasNoMatchingSpaces ? (
                <ServiceView.Section.Grid.Empty>
                  {getCategoryName() === 'starred' ? <StarIcon size={24} /> : <SearchIcon size={24} />}
                  <p>No {getCategoryName()} spaces found.</p>
                </ServiceView.Section.Grid.Empty>
              ) : (
                filteredSpaces?.map?.(copilotSpace => (
                  <SpacesCard
                    key={copilotSpace.owner ? `${copilotSpace.owner}/${copilotSpace.id}` : copilotSpace.id}
                    copilotSpace={copilotSpace}
                    spaceVisibilityEnabled={spaceVisibilityEnabled}
                    onDelete={handleCopilotSpaceDelete(copilotSpace)}
                    onClick={handleOnClickCopilotSpace}
                  />
                ))
              )}
            </ServiceView.Section.Grid>
          </ServiceView.Section>
        </div>
      </ServiceView.Container>
    </ErrorBoundary>
  )
}
