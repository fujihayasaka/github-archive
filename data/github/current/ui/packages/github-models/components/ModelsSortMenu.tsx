import {ActionList, ActionMenu} from '@primer/react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useSort} from '@github-ui/marketplace-common/SortContext'
import {sortOptions} from '@github-ui/marketplace-common/model-filter-options'

export function ModelsSortMenu() {
  const isPopularitySortEnabled = useFeatureFlag('github_models_popularity_sort')
  const {sort, setSort} = useSort()

  return (
    <ActionMenu>
      <ActionMenu.Button>
        <span className="fgColor-muted">Sort: </span>
        {sortOptions[sort] ?? sort}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="small">
        <ActionList selectionVariant="single" data-testid="creator-menu">
          {Object.entries(sortOptions)
            .filter(([option]) => option !== 'popularity' || isPopularitySortEnabled)
            .map(([option, label]) => (
              <ActionList.Item key={option} selected={option === sort} onSelect={() => setSort(option)}>
                {label}
              </ActionList.Item>
            ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
