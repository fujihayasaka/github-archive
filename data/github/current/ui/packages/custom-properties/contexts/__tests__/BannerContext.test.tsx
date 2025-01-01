import {jsonRoute} from '@github-ui/react-core/json-route'
import {render} from '@github-ui/react-core/test-utils'
import {useNavigate} from '@github-ui/use-navigate'
import {screen} from '@testing-library/react'
import {Route, Routes} from 'react-router-dom'

import {BANNER_HIDE_DELAY_MS, BannerProvider, useActiveBanner, useSetBanner} from '../BannerContext'

beforeEach(() => jest.useRealTimers())
describe('BannerProvider', () => {
  it('can set and clear banner', async () => {
    const {user} = render(
      <BannerProvider>
        <TestDisplayBannerComponent />
        <TestSetBannerComponent />
      </BannerProvider>,
    )

    expect(screen.getByText('No banner set')).toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Set'}))
    expect(screen.getByText('definition.created.success')).toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Clear'}))
    expect(screen.getByText('No banner set')).toBeInTheDocument()
  })

  it('banner is removed on navigation after a delay period has elapsed', async () => {
    jest.useFakeTimers()

    const SetPage = () => (
      <>
        Set page
        <TestSetBannerComponent />
        <TestGoToComponent to="/another" />
      </>
    )

    const AnotherPage = () => <>Another page</>

    const {user} = render(
      <BannerProvider>
        <TestDisplayBannerComponent />
        <Routes>
          <Route path="/set" Component={SetPage} />
          <Route path="/another" Component={AnotherPage} />
        </Routes>
      </BannerProvider>,
      {
        routes: [jsonRoute({path: '/set', Component: SetPage}), jsonRoute({path: '/another', Component: AnotherPage})],
        pathname: '/set',
      },
    )

    expect(screen.getByText('Set page')).toBeInTheDocument()
    await user.click(screen.getByRole('button', {name: 'Set'}))
    expect(screen.getByText('definition.created.success')).toBeInTheDocument()

    jest.advanceTimersByTime(BANNER_HIDE_DELAY_MS + 1)
    await user.click(screen.getByRole('button', {name: 'Go to'}))

    expect(screen.getByText('Another page')).toBeInTheDocument()
    expect(screen.queryByText('definition.created.success')).not.toBeInTheDocument()
  })

  it('banner is not removed on nav unless delay has elapsed', async () => {
    jest.useFakeTimers()

    const SetPage = () => (
      <>
        Set page
        <TestSetBannerComponent />
        <TestGoToComponent to="/another" />
      </>
    )

    const AnotherPage = () => <>Another page</>

    const {user} = render(
      <BannerProvider>
        <TestDisplayBannerComponent />
        <Routes>
          <Route path="/set" Component={SetPage} />
          <Route path="/another" Component={AnotherPage} />
        </Routes>
      </BannerProvider>,
      {
        routes: [jsonRoute({path: '/set', Component: SetPage}), jsonRoute({path: '/another', Component: AnotherPage})],
        pathname: '/set',
      },
    )

    expect(screen.getByText('Set page')).toBeInTheDocument()
    await user.click(screen.getByRole('button', {name: 'Set'}))
    expect(screen.getByText('definition.created.success')).toBeInTheDocument()

    jest.advanceTimersByTime(BANNER_HIDE_DELAY_MS - 1)
    await user.click(screen.getByRole('button', {name: 'Go to'}))

    expect(screen.getByText('Another page')).toBeInTheDocument()
    expect(screen.getByText('definition.created.success')).toBeInTheDocument()
  })
})

function TestDisplayBannerComponent() {
  const activeBanner = useActiveBanner()

  return <p>{activeBanner || 'No banner set'}</p>
}

function TestSetBannerComponent() {
  const setBanner = useSetBanner()

  return (
    <>
      <button onClick={() => setBanner('definition.created.success')}>Set</button>
      <button onClick={() => setBanner(null)}>Clear</button>
    </>
  )
}

function TestGoToComponent({to}: {to: string}) {
  const navigate = useNavigate()
  return <button onClick={() => navigate(to)}>Go to</button>
}
