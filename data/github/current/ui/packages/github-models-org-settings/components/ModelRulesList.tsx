import {useMemo} from 'react'
import {ActionList} from '@primer/react'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import type {Model} from '../types'
import {ModelRule} from './ModelRule'

export function ModelRulesList({models}: {models: Model[]}) {
  const {allowedModelKeys, isAllowlist} = useOrganizationAccessPolicy()
  const targetedModels = useMemo(() => {
    return models.filter(model => {
      const isModelAllowed = allowedModelKeys.has(model.key)
      return isAllowlist ? isModelAllowed : !isModelAllowed
    })
  }, [allowedModelKeys, isAllowlist, models])

  if (targetedModels.length < 1) {
    return (
      <div className="Box-body">
        <h3 className="py-5 text-center">
          No models have been <span>{isAllowlist ? 'allowed' : 'blocked'}</span> yet.
        </h3>
      </div>
    )
  }

  return (
    <ActionList className="Box-body px-0" aria-label="Model rules">
      {targetedModels.map(model => (
        <ModelRule model={model} key={`model-${isAllowlist ? 'allowed' : 'blocked'}-rule-${model.key}`} />
      ))}
    </ActionList>
  )
}
