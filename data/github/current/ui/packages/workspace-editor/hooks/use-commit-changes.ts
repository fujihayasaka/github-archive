import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useCallback, useState} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {assert, assertNonEmptyArray} from '../utilities/asserts'
import {mapChangedFileToServerDiff} from '../utilities/diff-helpers'
import {commitChangesUrl} from '../utilities/urls'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

/**
 * Arguments of the `commitChanges` function.
 */
type CommitChangesArgs = {
  // Commit message to commit with.
  commitMessage: string
  // Commit description with more details re the commit.
  commitDescription: string
  // Target branch name to commit to.
  headBranch: string
  // Expected head SHA of the target branch.
  headSHA: string
  // Repository owner username.
  ownerLogin: string
  // Associated pull request number.
  pullRequestNumber: string
  // The name of the repository to commit to.
  repoName: string
  // Selected file paths to commit.
  selectedFiles: Set<string>
  // Author email to commit with.
  authorEmail?: string
  // Create a new pull request instead of committing to an existing one.
  isQuickPull?: boolean
}

interface ICommitChangesSuccessResponse {
  commit_oid: string
  compare_url?: string
}

interface ICommitChangesFailureResponse {
  error?: string
}

type ICommitChangesResponse = ICommitChangesSuccessResponse | ICommitChangesFailureResponse

export function useCommitChanges() {
  const {getChangedFiles, getCurrentFileContent, markFilesCommitted} = useFilesContext()
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const [isInFlight, setIsInFlight] = useState(false)
  const {pullRequest, setPullRequest} = useCurrentPullRequest()

  const commitChanges = useCallback(
    async ({
      commitDescription,
      commitMessage,
      headBranch,
      headSHA,
      ownerLogin,
      pullRequestNumber,
      repoName,
      selectedFiles,
      authorEmail,
      isQuickPull,
    }: CommitChangesArgs) => {
      if (isInFlight) return

      const changedFiles = getChangedFiles().filter(f => selectedFiles.has(f.path))

      assertNonEmptyArray(changedFiles, 'No selected files to commit.')
      assert(commitMessage.trim().length > 0, 'No commit message provided.')

      try {
        const diffs = changedFiles.map(file => mapChangedFileToServerDiff(file))
        setIsInFlight(true)

        // TODO: use react query `useMutation` hook instead
        const response = await reactFetchJSON(
          commitChangesUrl({
            owner: ownerLogin,
            repo: repoName,
            pullNumber: pullRequestNumber,
          }),
          {
            method: 'POST',
            body: {
              branch: headBranch,
              branch_head: headSHA,
              message: commitMessage,
              description: commitDescription,
              diffs,
              author_email: authorEmail,
              is_quick_pull: isQuickPull,
            },
          },
        )

        const result: ICommitChangesResponse = await response.json()

        if ('commit_oid' in result === false) {
          // validate that if result JSON does not have commit ID, the HTTP request has failed
          // othwerwise it means that the server has returned an unexpected response data
          assert(!response.ok, 'Unexpected server response. Please try reloading the page and try again.')

          throw new Error(result.error ?? `HTTP ${response.status}`)
        }

        setPullRequest({
          ...pullRequest,
          headSHA: result.commit_oid,
        })

        if (payload.blobContents !== undefined) {
          const {content} = getCurrentFileContent(payload.path, payload.blobContents)
          payload.blobContents = content
        }

        markFilesCommitted(selectedFiles)

        return result
      } finally {
        setIsInFlight(false)
      }
    },
    [getChangedFiles, getCurrentFileContent, isInFlight, markFilesCommitted, payload, pullRequest, setPullRequest],
  )

  return {commitChanges, isInFlight}
}
