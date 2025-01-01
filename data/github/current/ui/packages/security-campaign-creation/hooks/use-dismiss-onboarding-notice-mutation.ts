import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetch} from '@github-ui/security-campaigns-shared/utils/fetch'

export function useDismissOnboardingNoticeMutation(path: string): UseMutationResult<void, Error, void> {
  return useMutation({
    mutationFn: () => {
      return fetch(path, {
        method: 'post',
      })
    },
  })
}
