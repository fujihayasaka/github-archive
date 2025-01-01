import {Checkbox, TreeView} from '@primer/react'
import {testIdProps} from '@github-ui/test-id-props'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import type {Model} from '../types'
import {useSelection} from '../contexts/SelectionContext'

interface ModelSelectionItemProps {
  model: Model
}

export function ModelSelectionItem({model}: ModelSelectionItemProps) {
  const {isAllowlist} = useOrganizationAccessPolicy()
  const {selectedModelKeys, selectModels, deselectModels} = useSelection()
  const isSelected = selectedModelKeys.has(model.key)

  return (
    <TreeView.Item
      id={`model-${isAllowlist ? 'allow' : 'block'}-${model.key}`}
      current={isSelected}
      aria-label={model.friendlyName}
      onSelect={() => (isSelected ? deselectModels([model.key]) : selectModels([model.key]))}
    >
      <div className="d-flex flex-items-center">
        <Checkbox
          value={model.key}
          className="mr-2"
          checked={isSelected}
          aria-label={`Select ${model.friendlyName}`}
          readOnly
          {...testIdProps(`model-checkbox-${model.key}`)}
        />
        {model.friendlyName}
      </div>
    </TreeView.Item>
  )
}
