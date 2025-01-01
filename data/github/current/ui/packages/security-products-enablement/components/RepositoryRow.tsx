import {useCallback} from 'react'
import capitalize from 'lodash-es/capitalize'
import pluralize from 'pluralize'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'
import {ListItem} from '@github-ui/list-view/ListItem'
import {repoSettingsSecurityAnalysisPath, repositoryPath} from '@github-ui/paths'
import {RelativeTime, Text} from '@primer/react'
import RepositoryConfigurationStatus from './RepositoryConfigurationStatus'
import {useRepositoryContext} from '../contexts/RepositoryContext'
import {useSelectedRepositoryContext} from '../contexts/SelectedRepositoryContext'
import {RenderContext, type Repository} from '../security-products-enablement-types'
import {useAppContext} from '../contexts/AppContext'

import styles from './RepositoryRow.module.css'

const RepositoryRow: React.FC = () => {
  const {organization, capabilities, user, renderContext} = useAppContext()
  const {repositories, totalRepositoryCount} = useRepositoryContext()
  const {selectedReposMap, setSelectedRepos, setSelectedReposCount} = useSelectedRepositoryContext()
  const selectedRepoIds = Object.keys(selectedReposMap).map(Number)
  const owner = renderContext === RenderContext.Organization ? organization : user

  const onRepoSelectToggle = useCallback(
    (repo: Repository) => {
      const {[repo.id]: selectedRepo, ...otherRepos} = selectedReposMap
      const updatedSelectedRepos = selectedRepo ? {...otherRepos} : {...otherRepos, [repo.id]: repo}

      // If the "select all" button was previously clicked, filter out repositories not on the current page
      // If the "select all" button was previously clicked, filter out repositories not on the current page
      if (selectedRepoIds.length === totalRepositoryCount) {
        const currentPageRepos = repositories.filter(r => r.id !== repo.id)
        setSelectedRepos(currentPageRepos.reduce((acc, currentRepo) => ({...acc, [currentRepo.id]: currentRepo}), {}))
        setSelectedReposCount(currentPageRepos.length)
      } else {
        setSelectedRepos(updatedSelectedRepos)
        setSelectedReposCount(Object.keys(updatedSelectedRepos).length)
      }
    },
    [
      selectedReposMap,
      selectedRepoIds.length,
      totalRepositoryCount,
      repositories,
      setSelectedRepos,
      setSelectedReposCount,
    ],
  )

  return (
    <>
      {repositories.map(repo => (
        <ListItem
          key={repo.id}
          title={
            <ListItemTitle
              value={repo.name}
              trailingBadges={[
                <ListItemTrailingBadge
                  key={repo.name}
                  title={`${capitalize(repo.visibility)}${repo.archived ? ' archive' : ''}`}
                  variant="secondary"
                />,
              ]}
              href={repoSettingsSecurityAnalysisPath({repo: {name: repo.name, ownerLogin: owner!}})}
              linkProps={{
                'data-hovercard-url': repositoryPath({owner: owner!, repo: repo.name, action: 'hovercard'}),
              }}
              headingClassName={styles.ListItemTitle_0}
            />
          }
          metadata={
            <>
              <ListItemMetadata variant="primary" alignment="right">
                <Text size="small" className={styles.Text}>
                  <RepositoryConfigurationStatus repository={repo} />
                </Text>
              </ListItemMetadata>
              {repo.licenses_required !== null &&
                capabilities.advancedSecurity.purchased &&
                capabilities.advancedSecurity.bundled && (
                  <ListItemMetadata>{pluralize('license', repo.licenses_required, true)} required</ListItemMetadata>
                )}
            </>
          }
          onSelect={() => onRepoSelectToggle(repo)}
          isSelected={!!selectedReposMap[repo.id]}
        >
          <ListItemMainContent>
            <ListItemDescription>
              Updated <RelativeTime datetime={repo.pushed_at} />
            </ListItemDescription>
          </ListItemMainContent>
        </ListItem>
      ))}
    </>
  )
}

export default RepositoryRow
