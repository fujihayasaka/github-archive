import {mockClientEnv} from '@github-ui/client-env/mock'
import {render, screen, within} from '@testing-library/react'
import {composeStory} from '@storybook/react'
import meta, {IssueItemMetadataExample as Example} from '../IssueItemMetadata.stories'
import {TEST_IDS} from '../../constants/test-ids'

const IssueItemMetadata = composeStory(Example, meta)

test('renders the assignee login', () => {
  render(<IssueItemMetadata />)

  expect(screen.getByAltText('monalisa')).toBeInTheDocument()
})

test('renders Copilot', () => {
  mockClientEnv({
    featureFlags: ['use_copilot_avatar'],
  })
  const CopilotExample = {
    ...Example,
    parameters: {
      relay: {
        ...Example.parameters.relay,
        mockResolvers: {
          Issue() {
            return {
              assignedActors: {
                edges: [
                  {
                    node: {
                      __typename: 'Bot',
                      login: 'copilot-swe-agent',
                      avatarUrl: 'https://github.com/github.png?size=40',
                      isCopilot: true,
                    },
                  },
                ],
              },
            }
          },
        },
      },
    },
  }
  const IssueItemMetadataWithCopilot = composeStory(CopilotExample, meta)
  render(<IssueItemMetadataWithCopilot />)

  expect(screen.getByTestId('copilot-avatar')).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'Copilot is assigned'})).toBeInTheDocument()
})

test('renders the linked pulls', () => {
  render(<IssueItemMetadata showLinkedPullRequests />)

  const linkedPulls = screen.getByTestId(TEST_IDS.listRowLinkedPullRequests)
  expect(within(linkedPulls).getByText('29')).toBeInTheDocument()
})

test('renders the issue comments', () => {
  render(<IssueItemMetadata />)

  const comments = screen.getByTestId(TEST_IDS.listRowComments)
  expect(within(comments).getByText('33')).toBeInTheDocument()
})
