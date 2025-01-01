import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {msw, http, HttpResponse} from '@github-ui/tests/msw'
import {getRepoCodeQualityIndexRoutePayload} from '../test-utils/mock-data'
import {codeQualityApp} from '../code-quality'
import type {RepoCodeQualityIndexResponse} from '../routes/repo-code-quality-index-route'
import {describe, expect, it} from '@github-ui/tests'
import {Grade} from '../types/grade'

function seedServer({mainQuery}: {mainQuery: RepoCodeQualityIndexResponse}) {
  msw.use(
    http.get('/:owner/:repo/security/quality', () => {
      return HttpResponse.json({
        payload: {
          repoCodeQualityIndexRoute: mainQuery,
        },
      })
    }),
  )

  seedRulesAndFilesServerEndpoints()
}

function seedRulesAndFilesServerEndpoints() {
  msw.use(
    http.get('/:owner/:repo/security/quality/rules', () => {
      return HttpResponse.json({rules: []})
    }),

    http.get('/:owner/:repo/security/quality/rules/:ruleId/files', () => {
      return HttpResponse.json({files: []})
    }),
  )
}

describe('code-quality', () => {
  it('Renders the RepoCodeQualityIndex component', async () => {
    const mainQuery = getRepoCodeQualityIndexRoutePayload()

    seedServer({mainQuery})
    render(codeQualityApp, '/:owner/:repo/security/quality', {
      appPayload: {},
    })

    expect(await screen.findByText('Code quality')).toBeInTheDocument()
  })

  it('Renders the RepoCodeQualityIndex component with embedded data', async () => {
    const mainQuery = getRepoCodeQualityIndexRoutePayload()

    seedRulesAndFilesServerEndpoints()

    render(codeQualityApp, '/:owner/:repo/security/quality', {
      embeddedData: {
        payload: {
          repoCodeQualityIndexRoute: mainQuery,
        },
      },
    })

    expect(await screen.findByText('Code quality')).toBeInTheDocument()
    expect(await screen.findByText('Improve the quality of the code in your repositories.')).toBeInTheDocument()
    expect(await screen.findByText(/Last scan:/)).toBeInTheDocument()
  })

  it('Renders the blankslate when there are no findings', async () => {
    const mainQuery = {
      ...getRepoCodeQualityIndexRoutePayload(),
      maintainability: {findingsCount: 0, grade: Grade.A},
      reliability: {findingsCount: 0, grade: Grade.A},
    }

    seedServer({mainQuery})
    render(codeQualityApp, '/:owner/:repo/security/quality', {
      embeddedData: {
        payload: {
          repoCodeQualityIndexRoute: mainQuery,
        },
      },
    })

    expect(await screen.findByText('No findings available!')).toBeInTheDocument()
  })

  it('Renders error state when rules endpoint fails', async () => {
    msw.use(
      http.get('/:owner/:repo/security/quality/rules', () => {
        return HttpResponse.json({rules: []}, {status: 500})
      }),
    )

    const mainQuery = getRepoCodeQualityIndexRoutePayload()

    render(codeQualityApp, '/:owner/:repo/security/quality', {
      embeddedData: {
        payload: {
          repoCodeQualityIndexRoute: mainQuery,
        },
      },
    })

    expect(await screen.findByText('An error has occurred.')).toBeInTheDocument()
    expect(await screen.findByText('Rules data could not be loaded right now.')).toBeInTheDocument()
  })
})
