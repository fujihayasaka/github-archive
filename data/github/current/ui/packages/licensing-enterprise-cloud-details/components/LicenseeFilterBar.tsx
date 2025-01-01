import {ActionList, ActionMenu, Stack} from '@primer/react'
import {SearchBar} from '@github-ui/licensing-common/components/SearchBar'
import {visualStudioFilterOptions} from '../types/visual-studio-filter-options'
import type {VisualStudioFilter} from '../types/visual-studio-filter-options'
import {clsx} from 'clsx'
import styles from './LicenseeFilterBar.module.css'

export interface LicenseeFilterBarProps {
  searchQuery: string
  setSearchQuery: (query: string) => void
  visualStudioFilter: VisualStudioFilter
  setVisualStudioFilter: (filter: VisualStudioFilter) => void
}

export function LicenseeFilterBar({
  searchQuery,
  setSearchQuery,
  visualStudioFilter,
  setVisualStudioFilter,
}: LicenseeFilterBarProps) {
  const selectedOption = visualStudioFilterOptions.find(o => o.value === visualStudioFilter)

  return (
    <Stack direction="horizontal" gap="condensed" className={clsx(styles.licenseeFilterBar)}>
      <div className="flex-1">
        <SearchBar
          searchQuery={searchQuery}
          setSearchQuery={setSearchQuery}
          placeholder="Search users"
          ariaLabel="Search users"
        />
      </div>
      <div>
        <ActionMenu>
          <ActionMenu.Button className="text-normal">
            Visual Studio: <span className={clsx(styles.selectedFilterOptionText)}>{selectedOption?.name}</span>
          </ActionMenu.Button>
          <ActionMenu.Overlay width="medium">
            <ActionList selectionVariant="single">
              {visualStudioFilterOptions.map(o => (
                <ActionList.Item
                  key={o.value}
                  selected={o.value === visualStudioFilter}
                  onSelect={() => setVisualStudioFilter(o.value)}
                >
                  {o.name}
                </ActionList.Item>
              ))}
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </div>
    </Stack>
  )
}
