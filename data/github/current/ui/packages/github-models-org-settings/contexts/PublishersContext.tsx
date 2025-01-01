import {createContext, type PropsWithChildren, useContext, useMemo} from 'react'
import type {Model, Publisher} from '../types'
import {useOrganizationAccessPolicy} from './OrganizationAccessPolicyContext'
import {areSetsDisjoint, isSubsetOf} from '../utils/set-utils'

interface PublishersContextType {
  /**
   * IDs of publishers where all their models are allowed.
   */
  allowedPublisherIds: Set<number>
  /**
   * IDs of publishers where none of their models are allowed.
   */
  blockedPublisherIds: Set<number>
  modelKeysByPublisherId: Map<number, Set<string>>
  publishersById: Map<number, Publisher>
}

const PublishersContext = createContext<PublishersContextType | undefined>(undefined)

export function usePublishers() {
  const context = useContext(PublishersContext)
  if (!context) throw new Error('usePublishers must be used within a PublishersProvider')
  return context
}

export function PublishersProvider({
  children,
  models,
  publishers,
}: PropsWithChildren<{models: Model[]; publishers: Publisher[]}>) {
  const {allowedModelKeys} = useOrganizationAccessPolicy()
  const publisherIds = publishers.map(publisher => publisher.id)
  const modelKeysByPublisherId = useMemo(
    () =>
      new Map(
        publishers.map(publisher => [
          publisher.id,
          new Set(models.filter(model => model.publisherId === publisher.id).map(model => model.key)),
        ]),
      ),
    [models, publishers],
  )
  const publishersById = useMemo(() => new Map(publishers.map(publisher => [publisher.id, publisher])), [publishers])
  const value = useMemo(
    () =>
      ({
        allowedPublisherIds: new Set(
          // Find publishers whose models are all allowed
          publisherIds.filter(publisherId =>
            isSubsetOf(allowedModelKeys, modelKeysByPublisherId.get(publisherId) ?? new Set()),
          ),
        ),
        blockedPublisherIds: new Set(
          // Find publishers who have no allowed models
          publisherIds.filter(publisherId =>
            areSetsDisjoint(allowedModelKeys, modelKeysByPublisherId.get(publisherId) ?? new Set()),
          ),
        ),
        modelKeysByPublisherId,
        publishersById,
      }) satisfies PublishersContextType,
    [allowedModelKeys, modelKeysByPublisherId, publisherIds, publishersById],
  )
  return <PublishersContext.Provider value={value}>{children}</PublishersContext.Provider>
}
