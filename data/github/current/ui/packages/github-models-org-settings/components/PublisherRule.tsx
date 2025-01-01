import {TrashIcon} from '@primer/octicons-react'
import {modelsCatalogPath} from '@github-ui/paths'
import {ActionList, Spinner} from '@primer/react'
import {PublisherAvatar} from '@github-ui/github-models/PublisherAvatar'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {usePublishers} from '../contexts/PublishersContext'
import {allowOrgModelsPayload, restrictOrgModelsPayload} from '../hooks/use-update-organization-access-policy'
import type {Publisher, BuildUpdatePolicyPayload} from '../types'

interface PublisherRuleProps {
  publisher: Publisher
}

export function PublisherRule({publisher}: PublisherRuleProps) {
  const {isAllowlist, isUpdatePending, pendingUpdateType, updateOrganizationAccessPolicy} =
    useOrganizationAccessPolicy()
  const {modelKeysByPublisherId} = usePublishers()

  return (
    <ActionList.LinkItem className="py-2" href={modelsCatalogPath({publisher: publisher.name})}>
      <ActionList.LeadingVisual>
        <PublisherAvatar publisher={publisher.name} logoUrl={publisher.logoUrl} darkModeIcon={publisher.darkModeIcon} />
      </ActionList.LeadingVisual>
      {publisher.name}
      <ActionList.Description>
        {publisher.totalModels}
        <span> {publisher.totalModels === 1 ? 'model' : 'models'}</span>
      </ActionList.Description>
      <ActionList.TrailingAction
        as="button"
        disabled={isUpdatePending}
        icon={() => {
          if (isUpdatePending && pendingUpdateType === 'rules') return <Spinner size="small" />
          return <TrashIcon />
        }}
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
