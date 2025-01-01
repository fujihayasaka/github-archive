import {FilesComponent} from '../routes/Files'
import {getFilesRoutePayload} from '../test-utils/files-changed/files-mock-data'
import {screen} from '@testing-library/react'
import type {FilesRoutePayload} from '../page-data/payloads/files'
import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'

import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'
import {getDiffstatPageData} from '../test-utils/header-mock-data'
import {mockCodeownersData} from '../test-utils/files-changed/codeowners-mock-data'

const server = setupServer()

function seedServer(labelCountPayload: NavigationCounterPageData) {
  server.use(
    http.get(/tab_counts/, () => {
      return HttpResponse.json(labelCountPayload)
    }),
    http.get(/diffstat/, () => {
      return HttpResponse.json(getDiffstatPageData())
    }),
    http.get(/codeowners/, () => {
      return HttpResponse.json(mockCodeownersData)
    }),
  )
}

function TestComponent(payload: FilesRoutePayload) {
  return (
    <FeatureFlagProvider features={{}}>
      <AliveTestProvider>
        <FilesComponent {...payload} />
      </AliveTestProvider>
    </FeatureFlagProvider>
  )
}

jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn(),
}))

describe('Files', () => {
  beforeAll(() => {
    server.listen()
  })
  beforeEach(() => {
    server.resetHandlers()
    const filesPayload = getFilesRoutePayload()
    const mockUseRoutePayload = useRoutePayload as jest.Mock
    mockUseRoutePayload.mockReturnValue(filesPayload)
  })
  afterAll(() => {
    server.close()
  })

  test('it renders the warning banner when the limits have been exceeded', async () => {
    const filesPayload = getFilesRoutePayload()
    const payloadWithExceededLimits: FilesRoutePayload = {
      ...filesPayload,
      pageLimits: {
        ...filesPayload.pageLimits,
        filesLimitExceeded: true,
        filesLimit: 300,
      },
    }

    const labelCountPayload: NavigationCounterPageData = {
      conversationCount: 1,
      checksCount: 4,
      filesChangedCount: 300,
      filesChangedCountLimitExceeded: true,
    }
    seedServer(labelCountPayload)

    renderWithClient(<TestComponent {...payloadWithExceededLimits} />)
    expect(await screen.findAllByText('This is my PR title :)')).toHaveLength(3)
    expect(screen.getByText(/Only the first 300 files are currently being shown/)).toBeInTheDocument()
    expect(await screen.findByText('300+')).toBeInTheDocument()
  })

  test('it does not render the warning banner when the limits have not been exceeded', async () => {
    const filesPayload = getFilesRoutePayload()
    const payloadWithNonExceededLimits: FilesRoutePayload = {
      ...filesPayload,
      diffSummaries: [],
      pageLimits: {
        ...filesPayload.pageLimits,
        filesLimitExceeded: false,
      },
    }

    const labelCountPayload: NavigationCounterPageData = {
      conversationCount: 1,
      checksCount: 4,
      filesChangedCount: 200,
      filesChangedCountLimitExceeded: false,
    }
    seedServer(labelCountPayload)

    renderWithClient(<TestComponent {...payloadWithNonExceededLimits} />)
    expect(await screen.findAllByText('This is my PR title :)')).toHaveLength(3)
    expect(screen.queryByText(/Only the first 300 files are currently being shown/)).not.toBeInTheDocument()
    expect(await screen.findByText('200')).toBeInTheDocument()
  })
})
