import {SortAscIcon, SortDescIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useSearchParams, useNavigate} from '@github-ui/use-navigate'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {useCallback} from 'react'
import type {SortKeyword} from './sort-options'
import {UI_SORT_VALUES} from './sort-options'

export function LabelSortMenu() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const currentSort = searchParams.get('sort')

  let option: SortKeyword = 'name'
  let direction: 'asc' | 'desc' = 'asc'

  if (currentSort) {
    const [optionPart, directionPart] = currentSort.split('-')
    if (UI_SORT_VALUES.includes(optionPart as SortKeyword)) option = optionPart as SortKeyword
    if (directionPart === 'asc' || directionPart === 'desc') direction = directionPart
  }

  const onSelectOption = useCallback(
    (newOption: SortKeyword) => {
      if (newOption === option) return
      const params = new URLSearchParams(searchParams)
      // Use descending as default for count, ascending for name
      const defaultDirection = newOption === 'count' ? 'desc' : 'asc'
      params.set('sort', `${newOption}-${defaultDirection}`)

      const href = `${ssrSafeWindow?.location.pathname}?${params.toString()}`
      navigate(href)
    },
    [searchParams, navigate, option],
  )

  const onSelectDirection = useCallback(
    (newDirection: 'asc' | 'desc') => {
      if (newDirection === direction) return
      const params = new URLSearchParams(searchParams)
      params.set('sort', `${option}-${newDirection}`)

      const href = `${ssrSafeWindow?.location.pathname}?${params.toString()}`
      navigate(href)
    },
    [direction, navigate, option, searchParams],
  )

  return (
    <ActionMenu>
      <ActionMenu.Button variant="invisible" leadingVisual={direction === 'asc' ? SortAscIcon : SortDescIcon}>
        Sort
      </ActionMenu.Button>

      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">
          <ActionList.Group>
            <ActionList.GroupHeading>Sort by</ActionList.GroupHeading>
            <ActionList.Item onSelect={() => onSelectOption('name')} selected={option === 'name'}>
              Name
            </ActionList.Item>
            <ActionList.Item onSelect={() => onSelectOption('count')} selected={option === 'count'}>
              Total issue count
            </ActionList.Item>
          </ActionList.Group>
          <ActionList.Group>
            <ActionList.GroupHeading>Order</ActionList.GroupHeading>
            <ActionList.Item key="ascending" selected={direction === 'asc'} onSelect={() => onSelectDirection('asc')}>
              <ActionList.LeadingVisual>
                <SortAscIcon />
              </ActionList.LeadingVisual>
              Ascending
            </ActionList.Item>
            <ActionList.Item
              key="descending"
              selected={direction === 'desc'}
              onSelect={() => onSelectDirection('desc')}
            >
              <ActionList.LeadingVisual>
                <SortDescIcon />
              </ActionList.LeadingVisual>
              Descending
            </ActionList.Item>
          </ActionList.Group>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
