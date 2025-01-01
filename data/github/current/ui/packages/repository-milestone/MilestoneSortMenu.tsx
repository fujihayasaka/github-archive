import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {ActionList, ActionMenu} from '@primer/react'
import {useCallback} from 'react'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {SortDescIcon} from '@primer/octicons-react'

export function MilestoneSortMenu() {
  const [searchParams] = useSearchParams()
  const sort = searchParams.get('sort')
  const direction = searchParams.get('direction')
  const navigate = useNavigate()
  const onSelectOption = useCallback(
    (sortKey: string | undefined, sortDirection: string | undefined) => {
      if (ssrSafeWindow) {
        const params = new URLSearchParams(searchParams)
        if (sortKey) {
          params.set('sort', sortKey)
        } else {
          params.delete('sort')
        }
        if (sortDirection) {
          params.set('direction', sortDirection)
        } else {
          params.delete('direction')
        }

        const href = `${ssrSafeWindow.location.pathname}?${params.toString()}`
        navigate(href)
      }
    },
    [navigate, searchParams],
  )

  return (
    <ActionMenu>
      <ActionMenu.Button variant="invisible" leadingVisual={SortDescIcon}>
        Sort
      </ActionMenu.Button>
      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">
          <ActionList.Group>
            <ActionList.GroupHeading>Sort by</ActionList.GroupHeading>
            <ActionList.Item
              onSelect={() => onSelectOption(undefined, undefined)}
              selected={!sort}
              role="menuitemradio"
            >
              Recently updated
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('due_date', 'desc')}
              selected={sort === 'due_date' && direction === 'desc'}
              role="menuitemradio"
            >
              Furthest due date
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('due_date', 'asc')}
              selected={sort === 'due_date' && direction === 'asc'}
              role="menuitemradio"
            >
              Closest due date
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('completeness', 'asc')}
              selected={sort === 'completeness' && direction === 'asc'}
              role="menuitemradio"
            >
              Least complete
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('completeness', 'desc')}
              selected={sort === 'completeness' && direction === 'desc'}
              role="menuitemradio"
            >
              Most complete
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('title', 'asc')}
              selected={sort === 'title' && direction === 'asc'}
              role="menuitemradio"
            >
              Alphabetical
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('title', 'desc')}
              selected={sort === 'title' && direction === 'desc'}
              role="menuitemradio"
            >
              Reverse alphabetical
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('count', 'desc')}
              selected={sort === 'count' && direction === 'desc'}
              role="menuitemradio"
            >
              Most issues
            </ActionList.Item>
            <ActionList.Item
              onSelect={() => onSelectOption('count', 'asc')}
              selected={sort === 'count' && direction === 'asc'}
              role="menuitemradio"
            >
              Fewest issues
            </ActionList.Item>
          </ActionList.Group>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
