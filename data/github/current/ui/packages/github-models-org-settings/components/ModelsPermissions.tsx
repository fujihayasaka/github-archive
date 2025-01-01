import {useCallback, useEffect, useState} from 'react'
import {FormControl, Radio, RadioGroup} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import type {AccessPolicyShowPayload} from '../types'
import {RulesTable} from './RulesTable'
import styles from './ModelsPermissions.module.css'
import {setDifference} from '../utils/set-utils'

export function ModelsPermissions() {
  const {models} = useRoutePayload<AccessPolicyShowPayload>()
  const {isAllowlist, isModelsEnabled, allowedModelKeys} = useOrganizationAccessPolicy()
  const anyRestrictions = useCallback(() => {
    const allModelKeys = new Set(models.map(model => model.key))
    const blockedModelKeys = setDifference(allModelKeys, allowedModelKeys)
    return isAllowlist || blockedModelKeys.size > 0
  }, [allowedModelKeys, isAllowlist, models])
  const [isAllSelected, setIsAllSelected] = useState(() => !anyRestrictions())

  useEffect(() => {
    if (anyRestrictions()) setIsAllSelected(false)
  }, [anyRestrictions])

  if (!isModelsEnabled) return null

  return (
    <RadioGroup
      onChange={newValue => setIsAllSelected(newValue === 'all')}
      name="models_restriction_setting"
      className={styles.radioGroup}
    >
      <RadioGroup.Label visuallyHidden>Select how models access should be restricted</RadioGroup.Label>
      <FormControl disabled={isAllowlist}>
        <Radio value="all" checked={isAllSelected} />
        <FormControl.Label>All publishers</FormControl.Label>
        <FormControl.Caption>
          Enable all current and future publishers available in the marketplace. All processing is handled securely by
          GitHub and Azure and never shared with external model providers.
        </FormControl.Caption>
      </FormControl>
      <FormControl>
        <Radio value="models" checked={!isAllSelected} />
        <FormControl.Label>Only select models</FormControl.Label>
        <FormControl.Caption>Create an enabled or disabled list.</FormControl.Caption>
      </FormControl>
      {!isAllSelected && (
        <div className="d-block ml-4 my-3">
          <RulesTable />
        </div>
      )}
    </RadioGroup>
  )
}
