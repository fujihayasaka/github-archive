import {useState} from 'react'
import {UnderlineNav} from '@primer/react'
import type {Model, Publisher} from '../types'
import {ModelRulesList} from './ModelRulesList'
import {AddRuleDialog} from './AddRuleDialog'
import {SelectionProvider} from '../contexts/SelectionContext'
import {RuleListTypeToggle} from './RuleListTypeToggle'
import {PublisherRulesList} from './PublisherRulesList'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {usePublishers} from '../contexts/PublishersContext'

export function RulesTable({models, publishers}: {models: Model[]; publishers: Publisher[]}) {
  const {allowedPublisherIds, blockedPublisherIds} = usePublishers()
  const {allowedModelKeys, isAllowlist, isModelsEnabled} = useOrganizationAccessPolicy()
  const totalAffectedPublishers = isAllowlist ? allowedPublisherIds.size : blockedPublisherIds.size
  const totalAffectedModels = isAllowlist ? allowedModelKeys.size : Math.max(models.length - allowedModelKeys.size, 0)
  const [isPublishersTabActive, setIsPublishersTabActive] = useState(
    totalAffectedPublishers > 0 || totalAffectedModels < 1,
  )
  const listNamePrefix = isAllowlist ? 'Allowed' : 'Blocked'

  if (!isModelsEnabled) return null

  return (
    <>
      <div className="mb-3 d-md-flex flex-row flex-justify-between flex-items-center">
        <RuleListTypeToggle />
        <SelectionProvider models={models} publishers={publishers}>
          <AddRuleDialog models={models} publishers={publishers} />
        </SelectionProvider>
      </div>
      <div className="Box Box--condensed">
        <UnderlineNav aria-label="View selected publishers or models">
          <UnderlineNav.Item
            as="button"
            aria-current={isPublishersTabActive ? 'location' : undefined}
            onSelect={() => setIsPublishersTabActive(true)}
            counter={totalAffectedPublishers}
          >
            {listNamePrefix} publishers
          </UnderlineNav.Item>
          <UnderlineNav.Item
            as="button"
            aria-current={!isPublishersTabActive ? 'location' : undefined}
            onSelect={() => setIsPublishersTabActive(false)}
            counter={totalAffectedModels}
          >
            {listNamePrefix} models
          </UnderlineNav.Item>
        </UnderlineNav>
        {isPublishersTabActive ? <PublisherRulesList publishers={publishers} /> : <ModelRulesList models={models} />}
      </div>
    </>
  )
}
