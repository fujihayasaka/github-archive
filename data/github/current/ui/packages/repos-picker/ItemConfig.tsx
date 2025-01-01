import type {ItemConfig, ItemLiterals} from '@github-ui/filter-picker'

import {ListItemRepoIcon} from './components/ListItemRepoIcon'
import {reposPickerRepositoriesPath} from './paths'
import type {PickerRepository, PickerScope} from './types'

export const itemLiterals: ItemLiterals = {
  itemName: 'repository',
  itemsName: 'repositories',
  listTitle: 'Repositories list',
}

export function getReposItemConfig(
  scope: PickerScope,
  getSearchUrl?: ItemConfig<PickerRepository>['getSearchUrl'],
): ItemConfig<PickerRepository> {
  return {
    ...itemLiterals,
    getSearchUrl: getSearchUrl || (query => reposPickerRepositoriesPath({scope, query})),
    onRenderItemLeadingVisual: repo => <ListItemRepoIcon visibility={repo.visibility} />,
    onRenderItemName: repo => getRepoName(repo, scope.type),
  }
}

export function getRepoName(repo: PickerRepository, scopeType: PickerScope['type']) {
  const showRepoOwner = scopeType !== 'organization' && scopeType !== 'user'
  if (showRepoOwner && repo.ownerLogin) {
    return `${repo.ownerLogin}/${repo.name}`
  }
  return repo.name
}
