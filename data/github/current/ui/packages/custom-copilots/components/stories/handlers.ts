// eslint-disable-next-line import/no-extraneous-dependencies
import {http} from 'msw'

export const handlers = [
  http.get('/github-copilot/chat/repositories/:repoId', () => {
    return Response.json({
      id: 1,
      name: 'example-repo',
      ownerLogin: 'github',
      commitOID: 'abc123',
      refInfo: {
        name: 'main',
      },
    })
  }),
  http.get('/_filter/repositories', () => {
    return Response.json({
      repositories: [
        {
          id: 1,
          nameWithOwner: 'github/example-repo',
        },
      ],
    })
  }),
]
