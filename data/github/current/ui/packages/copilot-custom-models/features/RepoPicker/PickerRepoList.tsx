import {ListView} from '@github-ui/list-view'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItem} from '@github-ui/list-view/ListItem'
import {GitHubAvatar} from '@github-ui/github-avatar'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {BaseRepo, OnSelect} from './types'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'

import styles from './PickerRepoList.module.css'

interface Props {
  onSelect: OnSelect
  repos: RepositoryPickerRepository$data[]
  selected: BaseRepo[] | undefined
}

export function PickerRepoList({onSelect, selected, repos}: Props) {
  return (
    <ListView isSelectable title="Repositories" variant="compact">
      {repos.map(repo => (
        <ListItem
          key={repo.nameWithOwner}
          isSelected={selected?.some(i => i.nameWithOwner === repo.nameWithOwner)}
          onSelect={isNowSelected => onSelect(repo, isNowSelected)}
          title={<ListItemTitle value={repo.nameWithOwner} />}
          className={styles.ListItem_0}
        >
          <ListItemLeadingContent>
            <ListItemLeadingVisual>
              <GitHubAvatar src={repo.owner.avatarUrl} square={repo.isInOrganization} size={16} />
            </ListItemLeadingVisual>
          </ListItemLeadingContent>
        </ListItem>
      ))}
    </ListView>
  )
}
