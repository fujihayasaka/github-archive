import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useCallback, useEffect, useState} from 'react'

import type {Collaborator, FileReference, MakeCAPIRequestType} from '../types'

export const useCopilotMetadata = ({
  setLoading,
  issueNumber,
  makeCAPIRequest,
  fileContext,
}: {
  setLoading: (loading: boolean) => void
  issueNumber: string
  makeCAPIRequest: MakeCAPIRequestType
  fileContext?: FileReference
}) => {
  const [collaborators, setCollaborators] = useState([] as Collaborator[])

  const {repoOwner, repoName, ref, path} = fileContext ?? {}

  const getCollaborators = useCallback(async () => {
    try {
      if (!fileContext) return ''

      const fetchedResponse = await verifiedFetchJSON(
        `/${repoOwner}/${repoName}/collaborator_prompt/${path}?ref=${ref}${issueNumber ? `&issue=${issueNumber}` : ''}`,
      )

      if (!fetchedResponse.ok) {
        throw new Error('Something went wrong')
      }

      const fetchedPrompt = await fetchedResponse.text()

      const body = {
        messages: [{role: 'user', content: fetchedPrompt}],
        model: 'gpt-4o-mini',
        stream: false,
        response_format: {
          type: 'json_schema',
          json_schema: {
            name: 'Collaborators',
            description: 'List of metadata objects for the top collaborators',
            strict: true,
            schema: {
              type: 'object',
              additionalProperties: false,
              properties: {
                collaborators: {
                  type: 'array',
                  items: {
                    type: 'object',
                    additionalProperties: false,
                    properties: {
                      id: {
                        type: 'integer',
                        description: "The collaborator's GitHub user ID.",
                      },
                      username: {
                        type: 'string',
                        description: "The collaborator's GitHub handle.",
                      },
                      avatar_url: {
                        type: 'string',
                        description: "The URL of the collaborator's GitHub user avatar.",
                      },
                      rank: {
                        type: 'string',
                        description: 'The rank assignment of the collaborator.',
                      },
                      explanation: {
                        type: 'string',
                        description: 'A brief 1-2 sentence description of the rank assignment.',
                      },
                    },
                    required: ['id', 'username', 'avatar_url', 'rank', 'explanation'],
                  },
                },
              },
              required: ['collaborators'],
            },
          },
          temperature: 0,
        },
      }

      const authTokenProvider = new CopilotAuthTokenProvider([])

      const token = await authTokenProvider.getAuthToken()

      const response = await makeCAPIRequest({
        basePath: 'https://api.githubcopilot.com',
        body,
        path: '/chat/completions',
        method: 'POST',
        streamingResponse: false,
        authToken: token,
        integrationId: 'copilot-directory',
      })

      if (!response.ok) throw new Error('Something went wrong')

      const responseJson = await response.json()

      return responseJson.choices[0]?.message?.content as string
    } catch {
      throw new Error('Something went wrong')
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (collaborators?.length) return

    getCollaborators()
      // eslint-disable-next-line github/no-then
      .then(
        result => {
          setLoading(false)
          setCollaborators(JSON.parse(result)?.collaborators as Collaborator[])
        },
        () => {
          setLoading(false)
        },
      )
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {collaborators, getCollaborators}
}
