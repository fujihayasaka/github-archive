import {useMutation} from '@tanstack/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import type {HeaderPageData} from '../page-data/payloads/header'
import {useHeaderPageDataQueryKey} from '../page-data/loaders/use-header-page-data'

export function useDismissAutomatedSecurityOnboardingMutation() {
  const headerPageDataQueryKey = useHeaderPageDataQueryKey()
  return useMutation({
    networkMode: 'always',
    mutationFn: ({dismissPath}: {dismissPath: string}) => {
      return reactFetchJSON(dismissPath, {method: 'POST'})
    },
    onSuccess: () => {
      queryClient.setQueryData(headerPageDataQueryKey, (old: HeaderPageData) => {
        const oldPageData = {...old}
        oldPageData.bannersData.banners.dependabotAutomatedSecurityUpdates.showOnboardingPopover = false
        return oldPageData
      })
    },
  })
}
