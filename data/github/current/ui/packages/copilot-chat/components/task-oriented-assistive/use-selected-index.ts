import {useCallback, useEffect, useState} from 'react'

export function useSelectedIndex(maximum: number) {
  const [selectedIndex, setSelectedIndex] = useState<number>(0)

  useEffect(() => {
    setSelectedIndex(prevIndex => {
      return Math.min(prevIndex, maximum)
    })
  }, [maximum])

  const selectPrevious = useCallback(() => {
    setSelectedIndex(prevIndex => (prevIndex === undefined ? maximum : prevIndex > 0 ? prevIndex - 1 : maximum))
  }, [maximum])

  const selectNext = useCallback(() => {
    setSelectedIndex(prevIndex => (prevIndex === undefined ? 0 : prevIndex < maximum ? prevIndex + 1 : 0))
  }, [maximum])

  return {
    selectedIndex,
    selectPrevious,
    selectNext,
  }
}
