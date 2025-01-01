import {TriangleDownIcon} from '@primer/octicons-react'
import {Button, SelectPanel} from '@primer/react'
import {type ComponentProps, type PropsWithChildren, useCallback, useMemo, useState} from 'react'

import type {Provider} from '../types'

type SelectPanelItem<T = unknown> = {
  id: string
  text: string
  item: T
}

export function ProviderPicker({
  id,
  providers,
  selected,
  onSelected,
  disabled,
}: {
  id?: string
  providers: Provider[]
  onSelected?: (provider: (typeof providers)[number]) => void
  selected?: Provider
  disabled?: boolean
}) {
  const [showPanel, setShowPanel] = useState(false)

  const [filter, setFilter] = useState('')

  const items = useMemo<Array<SelectPanelItem<Provider>>>(() => {
    const filterValue = filter.toLowerCase()
    return providers.flatMap(item => {
      if (filterValue && !item.name.toLowerCase().includes(filterValue)) return []
      return [selectPanelItemFromProvider(item)]
    })
  }, [filter, providers])

  const onSelectedChange = useCallback(
    (item: {item?: unknown} | undefined) => {
      if (!item?.item) return
      onSelected?.(item.item as Provider)
    },
    [onSelected],
  )

  const selectedItem = useMemo(() => {
    if (!selected) return undefined
    return selectPanelItemFromProvider(selected)
  }, [selected])

  // SelectPanel doesn't currently support being disabled, so we just customize the anchor
  // https://github.com/primer/react/blob/0e04210b4b257edf88dbd6e808a472703855fd54/packages/react/src/SelectPanel/SelectPanel.tsx#L144-L151
  const renderAnchor = useCallback(
    (props: PropsWithChildren<ComponentProps<typeof Button>>) => {
      const {children, ...rest} = props

      return (
        <Button trailingAction={TriangleDownIcon} {...rest} disabled={disabled}>
          {children}
        </Button>
      )
    },
    [disabled],
  )

  return (
    <SelectPanel
      id={id}
      title="Select provider"
      placeholder="Select provider"
      placeholderText="Search"
      renderAnchor={renderAnchor}
      items={items}
      open={showPanel}
      onOpenChange={setShowPanel}
      onFilterChange={setFilter}
      selected={selectedItem}
      onSelectedChange={onSelectedChange}
      overlayProps={{width: 'medium', height: 'auto'}}
      textInputProps={{
        ['aria-label']: 'Filter providers',
      }}
    />
  )
}

function selectPanelItemFromProvider(item: Provider): SelectPanelItem<Provider> {
  return {
    id: item.key,
    text: item.name,
    item,
  }
}
