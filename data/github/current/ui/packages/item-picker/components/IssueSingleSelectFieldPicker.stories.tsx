import type {Meta} from '@storybook/react'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {OperationDescriptor} from 'relay-runtime'
import {
  buildIssueFieldSingleSelect,
  TestIssueSingleSelectFieldPickerComponent,
} from '../test-utils/IssueSingleSelectFieldPickerHelpers'
import {IssueSingleSelectFieldPickerFieldGraphqlQuery} from './IssueSingleSelectFieldPicker'

type TestIssueSingleSelectFieldPickerProps = React.ComponentProps<typeof TestIssueSingleSelectFieldPickerComponent>

const environment = createMockEnvironment()

const meta = {
  title: 'ItemPicker/IssueSingleSelectFieldPicker',
  component: TestIssueSingleSelectFieldPickerComponent,
} satisfies Meta<typeof TestIssueSingleSelectFieldPickerComponent>

export default meta

const play = () => {
  environment.mock.queuePendingOperation(IssueSingleSelectFieldPickerFieldGraphqlQuery, {id: '123'})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      IssueFieldSingleSelect() {
        return buildIssueFieldSingleSelect()
      },
    })
  })
}

const args = {
  environment,
  shortcutEnabled: true,
  readonly: false,
  fieldId: '123',
  selectedOption: null,
  isLazy: true,
} satisfies TestIssueSingleSelectFieldPickerProps

export const Example = {
  args,
  play,
}
