import {TrashIcon} from '@primer/octicons-react'
import {modelPath} from '@github-ui/paths'
import {ActionList} from '@primer/react'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {usePublishers} from '../contexts/PublishersContext'
import {allowOrgModelsPayload, restrictOrgModelsPayload} from '../hooks/use-update-organization-access-policy'
import type {Model} from '../types'
import {PublisherAvatar} from './PublisherAvatar'

interface ModelRuleProps {
  model: Model
}

export function ModelRule({model}: ModelRuleProps) {
  const {isAllowlist, isUpdatePending, updateOrganizationAccessPolicy} = useOrganizationAccessPolicy()
  const {publishersById} = usePublishers()
  const publisher = publishersById.get(model.publisherId)
  if (!publisher) return null

  return (
    <ActionList.LinkItem className="py-2" href={modelPath(model)}>
      <ActionList.LeadingVisual>
        <PublisherAvatar publisher={publisher} />
      </ActionList.LeadingVisual>
      {model.friendlyName}
      <ActionList.Description>by {publisher.name}</ActionList.Description>
      <ActionList.TrailingAction
        as="button"
        disabled={isUpdatePending}
        icon={TrashIcon}
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
