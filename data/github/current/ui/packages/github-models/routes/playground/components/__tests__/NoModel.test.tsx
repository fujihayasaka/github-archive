import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockGettingStartedPayload, mockModel} from '../../__tests__/mocks'
import type {FeaturedModel} from '@github-ui/marketplace-common'
import {NoModel} from '../NoModel'

const featuredModel: FeaturedModel = {
  id: mockModel.id,
  registry: mockModel.registry,
  name: mockModel.name,
  friendly_name: mockModel.friendly_name,
  publisher: mockModel.publisher,
  summary: mockModel.summary,
  logo_url: mockModel.logo_url,
  light_mode_icon: mockModel.light_mode_icon,
  dark_mode_icon: mockModel.dark_mode_icon,
}

const getRoutePayload = () => ({
  routePayload: mockGettingStartedPayload({
    featuredModels: [featuredModel],
  }),
})

describe('NoModel', () => {
  test('renders the featured model view', async () => {
    render(<NoModel />, getRoutePayload())

    expect(screen.getByText('Welcome to GitHub Models')).toBeInTheDocument()
    expect(screen.queryByText('Build AI Apps with GitHub Models')).not.toBeInTheDocument()
    expect(screen.getByText(featuredModel.friendly_name)).toBeInTheDocument()
  })
})
