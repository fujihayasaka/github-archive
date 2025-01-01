import {mockClientEnv} from '@github-ui/client-env/mock'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'

import {getCopilotChatProviderProps, getDefaultReducerState} from '../../test-utils/mock-data'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {ThreadListView} from '../ThreadListView'

test('Deletes a thread when the trash icon is clicked', () => {
  const threads = new Map([
    [
      '1',
      {
        id: '1',
        name: 'Thread 1',
        currentReferences: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
    [
      '2',
      {
        id: '2',
        name: 'Thread 2',
        currentReferences: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
  ])

  render(
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={{
        ...getDefaultReducerState('2', undefined, 'immersive'),
        threads,
      }}
    >
      <ThreadListView />
    </CopilotChatProvider>,
  )

  // Verify both threads are initially rendered.
  expect(screen.getByText('Thread 1')).toBeInTheDocument()
  expect(screen.getByText('Thread 2')).toBeInTheDocument()

  // Click the trash icon for Thread 1.
  const deleteButton = screen.getByTestId('delete-thread-button-1')
  expect(deleteButton).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(deleteButton)

  // After deletion, Thread 1 should no longer be rendered while Thread 2 remains.
  expect(screen.queryByText('Thread 1')).not.toBeInTheDocument()
  expect(screen.getByText('Thread 2')).toBeInTheDocument()
})

test('Does not render the delete all button when there is one thread', () => {
  mockClientEnv({
    featureFlags: ['copilot_delete_all_conversations'],
  })
  expect(isFeatureEnabled('copilot_delete_all_conversations')).toBe(true)
  const threads = new Map([
    [
      '1',
      {
        id: '1',
        name: 'Thread 1',
        currentReferences: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
  ])

  render(
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={{...getDefaultReducerState('2', undefined, 'immersive'), threads}}
    >
      <ThreadListView />
    </CopilotChatProvider>,
  )

  const button = screen.queryByTestId('delete-all-threads-button') as HTMLButtonElement
  expect(button).not.toBeInTheDocument()
})

test('Renders the delete all button and the dialog box when with FF on and 2 threads', () => {
  mockClientEnv({
    featureFlags: ['copilot_delete_all_conversations'],
  })
  expect(isFeatureEnabled('copilot_delete_all_conversations')).toBe(true)
  const threads = new Map([
    [
      '1',
      {
        id: '1',
        name: 'Thread 1',
        currentReferences: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
    [
      '2',
      {
        id: '2',
        name: 'Thread 2',
        currentReferences: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
  ])

  render(
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={{...getDefaultReducerState('2', undefined, 'immersive'), threads}}
    >
      <ThreadListView />
    </CopilotChatProvider>,
  )

  const button = screen.queryByTestId('delete-all-threads-button') as HTMLButtonElement
  expect(button).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  const deleteDialog = screen.queryByTestId('delete-all-threads-dialog')
  expect(deleteDialog).toBeInTheDocument()
})
