import {codespacesPath} from '@github-ui/paths'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useCallback, useState} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {fetchQuery, graphql} from 'relay-runtime'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import type {useCopilotAgentDefaultBranchRepositoryQuery} from './__generated__/useCopilotAgentDefaultBranchRepositoryQuery.graphql'

const useCopilotAgentDefaultBranchRepositoryGraphQLQuery = graphql`
  query useCopilotAgentDefaultBranchRepositoryQuery($id: ID!) {
    node(id: $id) {
      ... on Repository {
        databaseId
        defaultBranchRef {
          name
        }
      }
    }
  }
`

export function useCopilotAgent({repoId, issueDatabaseId}: {repoId: string; issueDatabaseId: number}) {
  const environment = useRelayEnvironment()

  const [vscsTarget] = useLocalStorage<string | undefined>('vscs_target', undefined)
  const [vscsTargetUrl] = useLocalStorage<string | undefined>('vscs_target_url', undefined)
  const [codespaceCreationError, setCodespaceCreationError] = useState('')

  const handleCopilotAgentModeSubmit = useCallback(
    async (e?: React.MouseEvent) => {
      if (e) e.preventDefault()
      setCodespaceCreationError('')

      const newTab = ssrSafeWindow?.open('about:blank')

      try {
        const repoData = await fetchQuery<useCopilotAgentDefaultBranchRepositoryQuery>(
          environment,
          useCopilotAgentDefaultBranchRepositoryGraphQLQuery,
          {
            id: repoId,
          },
        ).toPromise()

        if (!repoData?.node) {
          setCodespaceCreationError('Failed to fetch repository data. Please try again.')
          newTab?.close()
          return
        }

        const formData = new FormData()
        formData.append('codespace[repository_id]', String(repoData.node?.databaseId))
        formData.append('codespace[ref]', repoData.node?.defaultBranchRef?.name || 'main')
        formData.append('codespace[issue_id]', String(issueDatabaseId))

        if (vscsTarget) {
          formData.append('codespace[vscs_target]', vscsTarget)
        }
        if (vscsTargetUrl) {
          formData.append('codespace[vscs_target_url]', vscsTargetUrl)
        }

        const result = await verifiedFetch(codespacesPath(), {
          method: 'POST',
          body: formData,
        })
        const body = await result.json()
        if (!result.ok) {
          setCodespaceCreationError(body.error)
          newTab?.close()
        } else {
          newTab?.location.assign(`/codespaces/${body.codespace_name}`)
        }
      } catch {
        setCodespaceCreationError('Codespace creation failed.')
        newTab?.close()
      }
    },
    [environment, issueDatabaseId, repoId, vscsTarget, vscsTargetUrl],
  )

  return {
    codespaceCreationError,
    setCodespaceCreationError,
    handleCopilotAgentModeSubmit,
  }
}
