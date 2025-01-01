import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {act, render, screen} from '@testing-library/react'
import {useEffect, useState} from 'react'

import {setupFlashContainer} from '../../test-utils/helpers'
import {PageBannerOutlet, setBanner} from '../PageBannerContext'

function TestBanner({onDismiss}: {onDismiss?: () => void}) {
  return (
    <div>
      Test Banner
      <button onClick={onDismiss}>Dismiss</button>
    </div>
  )
}

describe('PageBannerOutlet', () => {
  beforeEach(() => {
    setupFlashContainer()
  })

  it('renders a banner when setBanner is called', () => {
    render(<PageBannerOutlet />)
    act(() => setBanner(<TestBanner />))
    expect(screen.getByText('Test Banner')).toBeInTheDocument()
  })

  it('removes the banner when dismissed', async () => {
    render(<PageBannerOutlet />)
    expect(screen.queryByText('Test Banner')).not.toBeInTheDocument()

    act(() => setBanner(<TestBanner />))
    expect(screen.getByText('Test Banner')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', {name: 'Dismiss'}))

    expect(screen.queryByText('Test Banner')).not.toBeInTheDocument()
  })

  it('keeps the banner if the component that set it unmounts', () => {
    function BannerSetter() {
      useEffect(() => {
        setBanner(<TestBanner />)
        return () => {}
      }, [])
      return 'SETTER'
    }

    let hideSetter: () => void
    function Parent() {
      const [showSetter, setShowSetter] = useState(true)

      hideSetter = () => setShowSetter(false)

      return (
        <>
          {showSetter && <BannerSetter />}
          <PageBannerOutlet />
        </>
      )
    }

    expect(screen.queryByText('Test Banner')).not.toBeInTheDocument()
    render(<Parent />)
    expect(screen.getByText('Test Banner')).toBeInTheDocument()
    expect(screen.getByText('SETTER')).toBeInTheDocument()

    // @ts-expect-error Its fine typescript, its defined by now.
    expect(hideSetter).toBeTypeOf('function')
    act(() => hideSetter())

    expect(screen.queryByText('SETTER')).not.toBeInTheDocument()
    expect(screen.getByText('Test Banner')).toBeInTheDocument()
  })
})
