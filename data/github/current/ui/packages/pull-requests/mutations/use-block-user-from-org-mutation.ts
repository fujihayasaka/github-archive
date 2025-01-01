import {orgBlockedUsersPath} from '@github-ui/paths'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {produce} from 'immer'
import {verifiedFetch} from '@github-ui/verified-fetch'

export function useBlockUserFromOrgMutation(basePath: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      duration,
      hiddenReason,
      organizationLogin,
      notifyBlockedUser,
      shouldHideComment,
      userLogin,
    }: {
      duration: string
      shouldHideComment: boolean
      hiddenReason: string | undefined
      organizationLogin: string
      notifyBlockedUser: boolean
      userLogin: string
    }) => {
      const formData = new FormData()

      formData.append('duration', duration) // TODO: convert duration to a number
      formData.append('hide_comment', shouldHideComment.toString())
      if (hiddenReason) formData.append('hidden_reason', hiddenReason)
      formData.append('login', userLogin)
      formData.append('send_notification', notifyBlockedUser.toString())

      // Have to use verfiedFetch because wrappers like fetchWithErrorHandling don't support FormData
      await verifiedFetch(orgBlockedUsersPath({owner: organizationLogin}), {
        method: 'POST',
        body: formData,
        redirect: 'manual', // We don't want to follow the redirect, we can update the comments directly
      })
    },
    onSuccess: (_data, variables) => {
      return queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData

          // Find the comments of the blocked user
          const blockedUserComments = Object.values(oldMarkersData.threads).flatMap(
            thread =>
              thread.commentsData?.comments.filter(comment => comment.author?.login === variables.userLogin) || [],
          )

          if (blockedUserComments.length === 0) return oldMarkersData

          for (const comment of blockedUserComments) {
            comment.viewerCanBlockFromOrg = false
            comment.viewerCanUnblockFromOrg = true
            comment.isHidden = variables.shouldHideComment || comment.isHidden
            comment.minimizedReason = variables.hiddenReason || null
          }
        }),
      )
    },
  })
}
