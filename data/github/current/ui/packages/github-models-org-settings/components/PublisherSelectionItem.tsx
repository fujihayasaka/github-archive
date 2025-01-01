import {Checkbox, TreeView} from '@primer/react'
import {PublisherAvatar} from '@github-ui/github-models/PublisherAvatar'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {useSelection} from '../contexts/SelectionContext'
import type {Publisher, Model} from '../types'
import {ModelSelectionItem} from './ModelSelectionItem'
import {testIdProps} from '@github-ui/test-id-props'
import {isSubsetOf, setIntersection} from '../utils/set-utils'

export function PublisherSelectionItem({publisher, models}: {publisher: Publisher; models: Model[]}) {
  const {isAllowlist} = useOrganizationAccessPolicy()
  const {selectedModelKeys, selectModels, deselectModels} = useSelection()
  const modelsForPublisher = models.filter(model => model.publisherId === publisher.id)
  const modelKeysForPublisher = new Set(modelsForPublisher.map(model => model.key))
  const selectedModelKeysForPublisher = setIntersection(modelKeysForPublisher, selectedModelKeys)
  const anyModelsForPublisherSelected = selectedModelKeysForPublisher.size > 0
  const allModelsForPublisherSelected = isSubsetOf(selectedModelKeys, modelKeysForPublisher)
  const publisherModelUnits = publisher.totalModels === 1 ? 'model' : 'models'

  return (
    <TreeView.Item
      id={`publisher-${isAllowlist ? 'allow' : 'block'}-${publisher.id}`}
      current={allModelsForPublisherSelected}
      onSelect={() =>
        allModelsForPublisherSelected ? deselectModels(modelKeysForPublisher) : selectModels(modelKeysForPublisher)
      }
      aria-label={publisher.name}
    >
      <TreeView.LeadingVisual>
        <Checkbox
          indeterminate={anyModelsForPublisherSelected && !allModelsForPublisherSelected}
          checked={allModelsForPublisherSelected}
          aria-label={`Select ${publisher.name}`}
          readOnly
          {...testIdProps(`publisher-checkbox-${publisher.id}`)}
        />
      </TreeView.LeadingVisual>
      <div className="d-flex flex-items-center">
        <PublisherAvatar
          className="mr-2 box-shadow-none"
          publisher={publisher.name}
          logoUrl={publisher.logoUrl}
          darkModeIcon={publisher.darkModeIcon}
        />
        <span className="mr-1">{publisher.name}</span>
        <span className="text-small fgColor-muted">
          {selectedModelKeysForPublisher.size} of {publisher.totalModels} {publisherModelUnits} selected
        </span>
      </div>
      <TreeView.SubTree state="done" count={modelsForPublisher.length} aria-label={`Models from ${publisher.name}`}>
        {modelsForPublisher.map(model => (
          <ModelSelectionItem model={model} key={`model-${isAllowlist ? 'allow' : 'block'}-${model.key}`} />
        ))}
      </TreeView.SubTree>
    </TreeView.Item>
  )
}
