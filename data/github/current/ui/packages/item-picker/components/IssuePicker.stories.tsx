import type {Meta, StoryObj} from '@storybook/react'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {OperationDescriptor} from 'relay-runtime'
import {TestIssuePickerComponent, buildIssue} from '../test-utils/IssuePickerHelpers'

type Story = StoryObj<typeof TestIssuePickerComponent>

const meta = {
  title: 'ItemPicker/IssuePicker',
  component: TestIssuePickerComponent,
} satisfies Meta<typeof TestIssuePickerComponent>

export default meta

export const Example: Story = (function () {
  const environment = createMockEnvironment()
  const issues = Array.from({length: 20}, (_, i) => buildIssue({title: `issue${i + 1}`}))

  // this is the mock data for the initial query (IssuePickerHelpersTestQuery) that we don't want to mock here
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Node() {
        return {
          subIssues: {
            nodes: [],
          },
        }
      },
    })
  })

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Query() {
        return {
          commenters: {
            nodes: issues,
          },
          mentions: {
            nodes: [],
          },
          assignee: {
            nodes: [],
          },
          author: {
            nodes: [],
          },
          other: {
            nodes: [],
          },
        }
      },
    })
  })

  return {
    args: {
      environment,
    },
    render: args => {
      return <TestIssuePickerComponent {...args} />
    },
  }
})()
