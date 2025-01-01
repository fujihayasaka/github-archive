import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {RelayEnvironmentProvider} from 'react-relay'
import React from 'react'
import type {createMockEnvironment} from 'relay-test-utils'
import {IssueFieldPicker, type IssueField, type IssueFieldPickerProps} from '../components/IssueFieldPicker'
import {noop} from '@github-ui/noop'
import {Button} from '@primer/react'

export type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  overrides?: Partial<IssueFieldPickerProps>
} & Omit<IssueFieldPickerProps, 'onSelectionChange' | 'anchorElement' | 'owner' | 'repo' | 'activeIssueField'>

const defaultOverrides = {}
export function TestIssueFieldPickerComponent({
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
    <IssueFieldPicker
      onSelectionChange={noop}
      anchorElement={anchorProps => <Button {...anchorProps}>Select a field</Button>}
      owner="github"
      {...props}
    />
  )
}

export function buildIssueFieldText({name}: Pick<IssueField, 'name'>) {
  return {
    id: mockRelayId(),
    name,
    dataType: 'text',
    __typename: 'IssueFieldText',
  }
}
