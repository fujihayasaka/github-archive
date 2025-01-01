import {screen} from '@testing-library/react'

import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {noop} from '@github-ui/noop'
import {LABELS} from '@github-ui/timeline-items/Labels'

import {LoadDirectionPicker} from '../LoadDirectionPicker'

const userEvent = setupUserEvent()

type TestComponentProps = {
  loadFromTopFn?: () => void
  loadFromBottomFn?: () => void
  isLoading?: boolean
  setIsHovering?: (hovering: 'top' | 'bottom' | undefined) => void
  type?: 'load-top' | 'load-bottom'
}

function TestComponent(props: TestComponentProps = {}) {
  return (
    <LoadDirectionPicker
      loadFromTopFn={props.loadFromTopFn || noop}
      loadFromBottomFn={props.loadFromBottomFn || noop}
      isLoading={props.isLoading || false}
      setIsHovering={props.setIsHovering || noop}
      type={props.type || 'load-top'}
    />
  )
}

test('Hovering over the load over button show invoke setIsHovering method', async () => {
  const setIsHovering = jest.fn()

  render(TestComponent({setIsHovering}))

  const anchor = screen.getByTestId('issue-timeline-load-more-options-load-top')
  await userEvent.click(anchor)

  const loadOlderButton = screen.queryByText(LABELS.timeline.loadOlder)
  const loadNewerButton = screen.queryByText(LABELS.timeline.loadNewer)

  if (!loadOlderButton || !loadNewerButton) {
    throw new Error('Could not find load older or load newer button')
  }

  await userEvent.hover(loadOlderButton)
  expect(setIsHovering).toHaveBeenCalledWith('top')

  await userEvent.unhover(loadOlderButton)
  expect(setIsHovering).toHaveBeenCalledWith(undefined)

  await userEvent.hover(loadNewerButton)
  expect(setIsHovering).toHaveBeenCalledWith('bottom')

  await userEvent.unhover(loadOlderButton)
  expect(setIsHovering).toHaveBeenCalledWith(undefined)
})

test('Clicking on the load older button should invoke the loadFromTopFn method', async () => {
  const loadFromTopFn = jest.fn()
  render(TestComponent({loadFromTopFn}))

  const anchor = screen.getByTestId('issue-timeline-load-more-options-load-top')
  await userEvent.click(anchor)

  const loadOlderButton = screen.getByText(LABELS.timeline.loadOlder)
  await userEvent.click(loadOlderButton)

  expect(loadFromTopFn).toHaveBeenCalled()
})

test('Clicking on the load newer button should invoke the loadFromBottomFn method', async () => {
  const loadFromBottomFn = jest.fn()
  render(TestComponent({loadFromBottomFn}))

  const anchor = screen.getByTestId('issue-timeline-load-more-options-load-top')
  await userEvent.click(anchor)

  const loadOlderButton = screen.getByText(LABELS.timeline.loadNewer)
  await userEvent.click(loadOlderButton)

  expect(loadFromBottomFn).toHaveBeenCalled()
})
