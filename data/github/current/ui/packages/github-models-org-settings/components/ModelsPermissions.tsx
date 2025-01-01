import {useCallback, useState} from 'react'
import {FormControl, Radio, RadioGroup, ConfirmationDialog} from '@primer/react'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import type {Model, Publisher} from '../types'
import {RulesTable} from './RulesTable'
import {setDifference} from '../utils/set-utils'
import {allowAllOrgModelsPayload} from '../hooks/use-update-organization-access-policy'

export function ModelsPermissions({models, publishers}: {models: Model[]; publishers: Publisher[]}) {
  const {isAllowlist, isModelsEnabled, allowedModelKeys, updateOrganizationAccessPolicy} = useOrganizationAccessPolicy()
  const anyRestrictions = useCallback(() => {
    const allModelKeys = new Set(models.map(model => model.key))
    const blockedModelKeys = setDifference(allModelKeys, allowedModelKeys)
    return isAllowlist || blockedModelKeys.size > 0
  }, [allowedModelKeys, isAllowlist, models])
  const [isAllSelected, setIsAllSelected] = useState(() => !anyRestrictions())

  const [isAllowAllModelsDialogOpen, setIsAllowAllModelsDialogOpen] = useState(false)

  const saveAllPublishersSelected = (newValue: string | null) => {
    if (newValue === 'all') {
      // Clear all rules
      if (anyRestrictions()) {
        setIsAllowAllModelsDialogOpen(true)
      } else {
        allowAllModels()
      }
    } else {
      setIsAllSelected(false)
    }
  }

  const allowAllModels = () => {
    setIsAllSelected(true)
    updateOrganizationAccessPolicy(allowAllOrgModelsPayload())
    setIsAllowAllModelsDialogOpen(false)
  }

  if (!isModelsEnabled) return null

  return (
    <>
      {isAllowAllModelsDialogOpen && (
        <ConfirmationDialog
          title="Allow all models"
          onClose={gesture => (gesture === 'confirm' ? allowAllModels() : setIsAllowAllModelsDialogOpen(false))}
          confirmButtonContent="Allow all models"
          confirmButtonType="primary"
        >
          <p>
            Are you sure you want to allow all models? This will delete any existing model restrictions for your
            organization.
          </p>
        </ConfirmationDialog>
      )}
      <RadioGroup onChange={saveAllPublishersSelected} name="models_restriction_setting">
        <RadioGroup.Label visuallyHidden>Select how models access should be restricted</RadioGroup.Label>
        <FormControl>
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
            <RulesTable models={models} publishers={publishers} />
          </div>
        )}
      </RadioGroup>
    </>
  )
}
