import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {RelayEnvironmentProvider} from 'react-relay'
import React from 'react'
import type {createMockEnvironment} from 'relay-test-utils'
import {
  IssueSingleSelectFieldPicker,
  type IssueSingleSelectFieldPickerProps,
} from '../components/IssueSingleSelectFieldPicker'
import {noop} from '@github-ui/noop'
import {Button} from '@primer/react'

export type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  overrides?: Partial<IssueSingleSelectFieldPickerProps>
} & Omit<
  IssueSingleSelectFieldPickerProps,
  'onSelectionChange' | 'anchorElement' | 'owner' | 'repo' | 'activeIssueField'
>

const defaultOverrides = {}
export function TestIssueSingleSelectFieldPickerComponent({
  environment,
  overrides = defaultOverrides,
  ...props
}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <React.Suspense fallback="...Loading">
        <Component {...props} {...overrides} />
      </React.Suspense>
    </RelayEnvironmentProvider>
  )
}

function Component(props: Omit<TestComponentProps, 'environment'>) {
  return (
    <IssueSingleSelectFieldPicker
      onSelectionChange={noop}
      anchorElement={anchorProps => <Button {...anchorProps}>Select an option</Button>}
      {...props}
    />
  )
}

export function buildIssueFieldSingleSelect() {
  return {
    id: mockRelayId(),
    options: [
      {
        id: mockRelayId(),
        name: 'option 1',
        description: 'First option description',
        color: 'RED',
        __typename: 'IssueFieldSingleSelectOption',
      },
      {
        id: mockRelayId(),
        name: 'option 2',
        description: 'Second option description',
        color: 'BLUE',
        __typename: 'IssueFieldSingleSelectOption',
      },
      {
        id: mockRelayId(),
        name: 'option 3',
        description: 'Third option description',
        color: 'GREEN',
        __typename: 'IssueFieldSingleSelectOption',
      },
    ],
    __typename: 'IssueFieldSingleSelect',
  }
}
