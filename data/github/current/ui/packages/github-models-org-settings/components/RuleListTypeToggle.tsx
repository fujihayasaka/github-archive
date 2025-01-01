import {useState} from 'react'
import {ActionList, ActionMenu} from '@primer/react'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {allowOrgModelsPayload, restrictOrgModelsPayload} from '../hooks/use-update-organization-access-policy'
import type {UpdateOrganizationAccessPolicyPayload} from '../types'

export function RuleListTypeToggle() {
  const {isAllowlist, isModelsEnabled, isUpdatePending, updateOrganizationAccessPolicy} = useOrganizationAccessPolicy()
  const [open, setOpen] = useState(false)

  const handleSelect = (payload: UpdateOrganizationAccessPolicyPayload) => {
    setOpen(false)
    updateOrganizationAccessPolicy(payload)
  }

  if (!isModelsEnabled) return null

  return (
    <div className="flex-auto">
      <ActionMenu open={open} onOpenChange={val => setOpen(val)}>
        <ActionMenu.Button disabled={isUpdatePending}>
          {isAllowlist ? 'Enabled list' : 'Disabled list'}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          {!isUpdatePending && (
            <ActionList selectionVariant="single">
              <ActionList.Item selected={isAllowlist} onSelect={() => handleSelect(restrictOrgModelsPayload())}>
                Enabled list
                <ActionList.Description variant="block">
                  Select models that will be available for your organization.
                </ActionList.Description>
              </ActionList.Item>
              <ActionList.Item selected={!isAllowlist} onSelect={() => handleSelect(allowOrgModelsPayload())}>
                Disabled list
                <ActionList.Description variant="block">
                  Select models that will be blocked from use in your organization.
                </ActionList.Description>
              </ActionList.Item>
            </ActionList>
          )}
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}
