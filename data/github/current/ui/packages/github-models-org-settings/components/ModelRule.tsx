import {TrashIcon} from '@primer/octicons-react'
import {modelPath} from '@github-ui/paths'
import {ActionList, Spinner} from '@primer/react'
import {PublisherAvatar} from '@github-ui/github-models/PublisherAvatar'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {usePublishers} from '../contexts/PublishersContext'
import {allowOrgModelsPayload, restrictOrgModelsPayload} from '../hooks/use-update-organization-access-policy'
import type {Model} from '../types'

interface ModelRuleProps {
  model: Model
}

export function ModelRule({model}: ModelRuleProps) {
  const {isAllowlist, isUpdatePending, pendingUpdateType, updateOrganizationAccessPolicy} =
    useOrganizationAccessPolicy()
  const {publishersById} = usePublishers()
  const publisher = publishersById.get(model.publisherId)
  if (!publisher) return null

  return (
    <ActionList.LinkItem className="py-2" href={modelPath(model)}>
      <ActionList.LeadingVisual>
        <PublisherAvatar publisher={publisher.name} logoUrl={publisher.logoUrl} darkModeIcon={publisher.darkModeIcon} />
      </ActionList.LeadingVisual>
      {model.friendlyName}
      <ActionList.Description>by {publisher.name}</ActionList.Description>
      <ActionList.TrailingAction
        as="button"
        disabled={isUpdatePending}
        icon={() => {
          if (isUpdatePending && pendingUpdateType === 'rules') return <Spinner size="small" />
          return <TrashIcon />
        }}
        label={`Delete ${model.friendlyName}`}
        onClick={() => {
          const payloadParams = {modelKeys: [model.key]}
          const payload = isAllowlist ? restrictOrgModelsPayload(payloadParams) : allowOrgModelsPayload(payloadParams)
          updateOrganizationAccessPolicy(payload)
        }}
      />
    </ActionList.LinkItem>
  )
}
