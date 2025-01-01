// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useState, useCallback, useEffect} from 'react'

const useAccordionStates = ({items, hasSingleItemOpen = false}: {items: unknown[]; hasSingleItemOpen?: boolean}) => {
  const [itemStates, setItemStates] = useState(items.map(() => false))

  const updateItem = useCallback(
    (index: number, state: boolean) => {
      const newStates = itemStates.map((oldState, i) => (i === index ? state : hasSingleItemOpen ? false : oldState))
      setItemStates(newStates)
    },
    [itemStates, hasSingleItemOpen],
  )

  useEffect(() => {
    setItemStates(items.map(() => false))
  }, [items])

  return {
    itemStates,
    updateItem,
  }
}

export default useAccordionStates
