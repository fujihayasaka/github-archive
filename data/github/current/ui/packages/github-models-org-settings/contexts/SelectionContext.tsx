import {createContext, type PropsWithChildren, useCallback, useContext, useEffect, useMemo, useState} from 'react'
import type {Model, Publisher} from '../types'
import {useOrganizationAccessPolicy} from './OrganizationAccessPolicyContext'
import {usePublishers} from './PublishersContext'
import {isSubsetOf, setDifference, setIntersection} from '../utils/set-utils'

interface SelectionContextType {
  selectedModelKeys: Set<string>
  partiallySelectedPublisherIds: Set<number>
  fullySelectedPublisherIds: Set<number>
  deselectModels: (keysToDeselect: string[] | Set<string>) => void
  selectModels: (keysToSelect: string[] | Set<string>) => void
}

const SelectionContext = createContext<SelectionContextType | undefined>(undefined)

export function useSelection() {
  const context = useContext(SelectionContext)
  if (!context) throw new Error('useSelection must be used within a SelectionProvider')
  return context
}

export function SelectionProvider({
  children,
  models,
  publishers,
}: PropsWithChildren<{
  models: Model[]
  publishers: Publisher[]
}>) {
  const {allowedModelKeys, isAllowlist} = useOrganizationAccessPolicy()
  const [selectedModelKeys, setSelectedModelKeys] = useState(() => {
    return isAllowlist
      ? allowedModelKeys
      : new Set(models.map(model => model.key).filter(key => !allowedModelKeys.has(key)))
  })
  const {modelKeysByPublisherId} = usePublishers()
  const partiallySelectedPublisherIds = useMemo(() => {
    return new Set(
      publishers
        .map(publisher => publisher.id)
        .filter(publisherId => {
          const publisherModelKeys = modelKeysByPublisherId.get(publisherId) ?? new Set()
          const selectedPublisherModelKeys = setIntersection(selectedModelKeys, publisherModelKeys)
          return selectedPublisherModelKeys.size > 0
        }),
    )
  }, [modelKeysByPublisherId, publishers, selectedModelKeys])
  const fullySelectedPublisherIds = useMemo(() => {
    return new Set(
      publishers
        .map(publisher => publisher.id)
        .filter(publisherId => {
          const publisherModelKeys = modelKeysByPublisherId.get(publisherId) ?? new Set()
          return isSubsetOf(selectedModelKeys, publisherModelKeys)
        }),
    )
  }, [modelKeysByPublisherId, publishers, selectedModelKeys])

  const deselectModels = useCallback(
    (keysToDeselect: string[] | Set<string>) => {
      setSelectedModelKeys(setDifference(selectedModelKeys, new Set(keysToDeselect)))
    },
    [selectedModelKeys, setSelectedModelKeys],
  )

  const selectModels = useCallback(
    (keysToSelect: string[] | Set<string>) => {
      setSelectedModelKeys(new Set([...selectedModelKeys, ...keysToSelect]))
    },
    [selectedModelKeys, setSelectedModelKeys],
  )

  const value = useMemo(
    () =>
      ({
        deselectModels,
        fullySelectedPublisherIds,
        partiallySelectedPublisherIds,
        selectedModelKeys,
        selectModels,
      }) satisfies SelectionContextType,
    [deselectModels, fullySelectedPublisherIds, partiallySelectedPublisherIds, selectedModelKeys, selectModels],
  )

  useEffect(() => {
    setSelectedModelKeys(
      isAllowlist
        ? allowedModelKeys
        : new Set(models.map(model => model.key).filter(key => !allowedModelKeys.has(key))),
    )
  }, [allowedModelKeys, isAllowlist, models])

  return <SelectionContext.Provider value={value}>{children}</SelectionContext.Provider>
}
