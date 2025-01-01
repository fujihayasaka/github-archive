import {encodePart, orgBlockedUsersPath} from '@github-ui/paths'
import {fetchWithErrorHandling} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {produce} from 'immer'

export function useUnblockUserFromOrgMutation(basePath: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({organizationLogin, userLogin}: {organizationLogin: string; userLogin: string}) => {
      await fetchWithErrorHandling(`${orgBlockedUsersPath({owner: organizationLogin})}/${encodePart(userLogin)}`, {
        method: 'DELETE',
        redirect: 'manual', // We don't want to follow the redirect, we can update the comments directly
      })
    },
    onSuccess: (_data, variables) => {
      return queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData

          // Find the comments of the unblocked user
          const unblockedUserComments = Object.values(oldMarkersData.threads).flatMap(
            thread =>
              thread.commentsData?.comments.filter(comment => comment.author?.login === variables.userLogin) || [],
          )

          if (unblockedUserComments.length === 0) return oldMarkersData

          for (const comment of unblockedUserComments) {
            comment.viewerCanBlockFromOrg = true
            comment.viewerCanUnblockFromOrg = false
          }
        }),
      )
    },
  })
}
