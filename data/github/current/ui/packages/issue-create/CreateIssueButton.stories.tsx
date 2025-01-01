import type {Meta, StoryObj} from '@storybook/react'
import {CreateIssueButton, type CreateIssueButtonProps} from './CreateIssueButton'
import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'
import {MemoryRouter} from 'react-router-dom'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {AppContext} from '@github-ui/react-core/app-context'

const meta = {
  title: 'IssueCreate',
  component: CreateIssueButton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    size: {control: 'inline-radio', options: ['small', 'medium']},
  },
} satisfies Meta<typeof CreateIssueButton>

export default meta
type Story = StoryObj<typeof CreateIssueButton>

const defaultArgs: Partial<CreateIssueButtonProps> = {
  label: 'Create issue',
}

function RelayStoryComponent({children}: {children: React.ReactNode}) {
  const environment = createMockEnvironment()

  return <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
}

export const CreateIssueButtonExample: Story = {
  args: {
    ...defaultArgs,
  },
  decorators: [
    Story => (
      <AppContext.Provider
        value={{
          routes: [
            jsonRoute({path: '/issues/new', Component: ({children}: React.PropsWithChildren) => <>{children}</>}),
          ],
        }}
      >
        <RelayStoryComponent>
          <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
            <Story />
          </MemoryRouter>
        </RelayStoryComponent>
      </AppContext.Provider>
    ),
  ],
}
