import type {Meta} from '@storybook/react'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {OperationDescriptor} from 'relay-runtime'
import {buildIssueFieldText, TestIssueFieldPickerComponent} from '../test-utils/IssueFieldPickerHelpers'

import {IssueFieldPickerGraphqlQuery} from './IssueFieldPicker'

type TestIssueFieldPickerProps = React.ComponentProps<typeof TestIssueFieldPickerComponent>

const environment = createMockEnvironment()

const meta = {
  title: 'ItemPicker/IssueFieldPicker',
  component: TestIssueFieldPickerComponent,
} satisfies Meta<typeof TestIssueFieldPickerComponent>

export default meta

const play = () => {
  environment.mock.queuePendingOperation(IssueFieldPickerGraphqlQuery, {name: 'github', issueFieldsPageSize: 50})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Organization() {
        return {
          issueFields: {
            edges: [
              {node: buildIssueFieldText({name: 'Status'})},
              {node: buildIssueFieldText({name: 'Priority'})},
              {node: buildIssueFieldText({name: 'DRI'})},
            ],
          },
        }
      },
    })
  })
}

const args = {
  environment,
  shortcutEnabled: true,
  readonly: false,
  fieldsSet: [],
} satisfies TestIssueFieldPickerProps

export const Example = {
  args,
  play,
}
