import {useState, useEffect} from 'react'

export function useCheckboxSelection<T>(items: T[], getItemId: (item: T) => number) {
  const [selectedItems, setSelectedItems] = useState<Set<number>>(new Set())
  const [selectAll, setSelectAll] = useState(false)

  const handleSelectItem = (itemId: number) => {
    setSelectedItems(prev => {
      const updated = new Set(prev)
      if (updated.has(itemId)) {
        updated.delete(itemId)
      } else {
        updated.add(itemId)
      }
      return updated
    })
  }

  const handleSelectAll = () => {
    if (selectAll) {
      setSelectedItems(new Set())
    } else {
      const allItemIds = new Set(items.map(getItemId))
      setSelectedItems(allItemIds)
    }
    setSelectAll(!selectAll)
  }

  // Reset selection when the items array changes
  useEffect(() => {
    setSelectedItems(new Set())
    setSelectAll(false)
  }, [items])

  return {
    selectedItems,
    selectAll,
    handleSelectItem,
    handleSelectAll,
  }
}
