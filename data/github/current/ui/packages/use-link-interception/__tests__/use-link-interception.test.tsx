// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook, screen, fireEvent, render} from '@testing-library/react'
import {useLinkInterception} from '../use-link-interception'

test('Renders the useLinkInterception hook', () => {
  // Create a mock function
  const onLinkClick = jest.fn()

  render(<a href="#test">Test Link</a>)
  const link = screen.getByText('Test Link')

  renderHook(() => useLinkInterception({htmlContainer: link, onLinkClick, openLinksInNewTab: false}))
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(link)

  expect(onLinkClick).toHaveBeenCalled()
})
