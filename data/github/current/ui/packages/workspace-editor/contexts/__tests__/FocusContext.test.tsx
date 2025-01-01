import '../../test-utils/mocks'

import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useEffect, useRef} from 'react'

import {FocusContextProvider, useFocus} from '../FocusContext'

function TestComponent() {
  const {setFocusTarget, focusTarget} = useFocus()
  const headerRef = useRef<HTMLDivElement>(null)
  const footerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    setFocusTarget('header', headerRef.current)
    setFocusTarget('footer', footerRef.current)
  }, [setFocusTarget])

  return (
    <div>
      <div ref={headerRef} tabIndex={-1} data-testid="header">
        Header
      </div>
      <div ref={footerRef} tabIndex={-1} data-testid="footer">
        Footer
      </div>
      <button onClick={() => focusTarget('header')}>Focus Header</button>
      <button onClick={() => focusTarget('footer')}>Focus Footer</button>
    </div>
  )
}

describe('FocusContext', () => {
  test('should focus the header when "Focus Header" button is clicked', async () => {
    const {user} = render(
      <FocusContextProvider>
        <TestComponent />
      </FocusContextProvider>,
    )

    const header = screen.getByTestId('header')
    const focusHeaderButton = screen.getByText('Focus Header')

    await user.click(focusHeaderButton)
    expect(header).toHaveFocus()
  })

  test('should focus the footer when "Focus Footer" button is clicked', async () => {
    const {user} = render(
      <FocusContextProvider>
        <TestComponent />
      </FocusContextProvider>,
    )

    const footer = screen.getByTestId('footer')
    const focusFooterButton = screen.getByText('Focus Footer')

    await user.click(focusFooterButton)
    expect(footer).toHaveFocus()
  })

  test('should not have focus initially', () => {
    render(
      <FocusContextProvider>
        <TestComponent />
      </FocusContextProvider>,
    )

    const header = screen.getByTestId('header')
    const footer = screen.getByTestId('footer')

    expect(header).not.toHaveFocus()
    expect(footer).not.toHaveFocus()
  })

  test('should switch focus between header and footer', async () => {
    const {user} = render(
      <FocusContextProvider>
        <TestComponent />
      </FocusContextProvider>,
    )

    const header = screen.getByTestId('header')
    const footer = screen.getByTestId('footer')
    const focusHeaderButton = screen.getByText('Focus Header')
    const focusFooterButton = screen.getByText('Focus Footer')

    await user.click(focusHeaderButton)
    expect(header).toHaveFocus()

    await user.click(focusFooterButton)
    expect(footer).toHaveFocus()
  })

  test('should maintain focus on header when "Focus Header" button is clicked multiple times', async () => {
    const {user} = render(
      <FocusContextProvider>
        <TestComponent />
      </FocusContextProvider>,
    )

    const header = screen.getByTestId('header')
    const focusHeaderButton = screen.getByText('Focus Header')

    await user.click(focusHeaderButton)
    expect(header).toHaveFocus()

    await user.click(focusHeaderButton)
    expect(header).toHaveFocus()
  })
})
