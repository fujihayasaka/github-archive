// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useEnsureOrgName} from './use-ensure-org-name'
import type {ActionMenuButtonOption} from '../traditional/components/ActionMenuButton'
import type {MenuItem} from '../types'
import {useCallback, useMemo, useState} from 'react'
import {useCreateMutator} from './use-fetchers'
import {seatManagementEndpoint} from '../traditional/helpers/api-endpoints'

export function useOptions(config: {items: MenuItem[]; controls: string; defaultOption?: ActionMenuButtonOption}) {
  const org = useEnsureOrgName()
  const {addToast} = useToastContext()

  // options
  const [options, setOptions] = useState<ActionMenuButtonOption[]>(config.items)

  const normalizedOptions = useMemo(() => {
    return options.map(item => ({
      ...item,
      testId: `cfb-policy-option-${item.title}`,
    }))
  }, [options])

  // derrived selected
  const selected = useMemo(() => {
    return options.find(option => option.selected) ?? config.defaultOption
  }, [options, config.defaultOption])

  // mutations
  const useCopilotSettingsMutation = useCreateMutator(seatManagementEndpoint, {org})
  // eslint-disable-next-line react-hooks/react-compiler
  const [updateOption, loading] = useCopilotSettingsMutation<Record<string, string>, {success: boolean}>({
    resource: 'policies',
    method: 'PUT',
  })

  const onSelect = useCallback(
    async (item: ActionMenuButtonOption) => {
      updateOption({
        payload: {
          [config.controls]: item.value as string,
        },
        onError(e) {
          let message = 'Something went wrong. Please try again later.'
          if (e && typeof e === 'object' && 'message' in e) message = String(e.message)

          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            message,
            role: 'alert',
            type: 'error',
          })
        },
        onComplete(data) {
          if (data && data.success) {
            setOptions(prev => {
              return prev.map(option => {
                option.selected = option.id === item.id
                return option
              })
            })
          }
        },
      })
    },
    [config.controls, updateOption, addToast],
  )

  return {
    loading,
    ///
    selected,
    onSelect,
    ///
    options: normalizedOptions,
  }
}
