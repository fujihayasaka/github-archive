import {screen} from '@testing-library/react'

import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {noop} from '@github-ui/noop'

import {LoadMore, type LoadMoreCallbackFn} from '../LoadMore'
import {LABELS} from '@github-ui/timeline-items/Labels'

const userEvent = setupUserEvent()

type TestComponentProps = {
  numberOfRemainingItems?: number
  loadFromTopFn?: LoadMoreCallbackFn
  loadFromBottomFn?: LoadMoreCallbackFn
  onLoadAllComplete?: (loadedMoreFromTop?: boolean) => void
  children?: React.ReactNode
  type?: 'load-top' | 'load-bottom'
  lastItemInTopTimelineIsComment?: boolean
  firstItemInBottomTimelineIsComment?: boolean
}

function TestComponent(props: TestComponentProps = {}) {
  return (
    <LoadMore
      numberOfRemainingItems={props.numberOfRemainingItems || 0}
      loadFromTopFn={props.loadFromTopFn || noop}
      loadFromBottomFn={props.loadFromBottomFn || noop}
      onLoadAllComplete={props.onLoadAllComplete || noop}
      type={props.type || 'load-top'}
      lastItemInTopTimelineIsComment={props.lastItemInTopTimelineIsComment || false}
      firstItemInBottomTimelineIsComment={props.firstItemInBottomTimelineIsComment || false}
    >
      {props.children || <div>Test</div>}
    </LoadMore>
  )
}

test('Clicking the button in LoadAll mode will load all the remaining items', async () => {
  const loadFromTopFn = jest.fn()

  render(
    TestComponent({
      loadFromTopFn,
      numberOfRemainingItems: 10,
    }),
  )

  const loadAllButton = screen.getByTestId('issue-timeline-load-more-load-top')

  await userEvent.click(loadAllButton)

  expect(loadFromTopFn).toHaveBeenCalledWith(10, {onComplete: expect.any(Function)})
})

test('When more than 150 items are left, the user can choose to load them from the bottom', async () => {
  const loadFromBottomFn = jest.fn()

  render(
    TestComponent({
      loadFromBottomFn,
      numberOfRemainingItems: 170,
    }),
  )

  const anchor = screen.getByTestId('issue-timeline-load-more-options-load-top')
  await userEvent.click(anchor)

  const loadNewerButton = screen.queryByText(LABELS.timeline.loadNewer)

  if (!loadNewerButton) {
    throw new Error('Could not find load newer button')
  }

  await userEvent.click(loadNewerButton)

  expect(loadFromBottomFn).toHaveBeenCalledWith(150, {onComplete: expect.any(Function)})
})
