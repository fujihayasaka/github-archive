import {TrashIcon} from '@primer/octicons-react'
import {modelsCatalogPath} from '@github-ui/paths'
import {ActionList} from '@primer/react'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {usePublishers} from '../contexts/PublishersContext'
import {allowOrgModelsPayload, restrictOrgModelsPayload} from '../hooks/use-update-organization-access-policy'
import type {Publisher, BuildUpdatePolicyPayload} from '../types'
import {PublisherAvatar} from './PublisherAvatar'

interface PublisherRuleProps {
  publisher: Publisher
}

export function PublisherRule({publisher}: PublisherRuleProps) {
  const {isAllowlist, isUpdatePending, updateOrganizationAccessPolicy} = useOrganizationAccessPolicy()
  const {modelKeysByPublisherId} = usePublishers()

  return (
    <ActionList.LinkItem className="py-2" href={modelsCatalogPath({publisher: publisher.name})}>
      <ActionList.LeadingVisual>
        <PublisherAvatar publisher={publisher} />
      </ActionList.LeadingVisual>
      {publisher.name}
      <ActionList.Description>
        {publisher.totalModels}
        <span> {publisher.totalModels === 1 ? 'model' : 'models'}</span>
      </ActionList.Description>
      <ActionList.TrailingAction
        as="button"
        disabled={isUpdatePending}
        icon={TrashIcon}
        label={`Delete ${publisher.name}`}
        onClick={() => {
          const payloadParams: BuildUpdatePolicyPayload = {
            modelKeys: modelKeysByPublisherId.get(publisher.id),
            publisherIds: [publisher.id],
          }
          const payload = isAllowlist ? restrictOrgModelsPayload(payloadParams) : allowOrgModelsPayload(payloadParams)
          updateOrganizationAccessPolicy(payload)
        }}
      />
    </ActionList.LinkItem>
  )
}
