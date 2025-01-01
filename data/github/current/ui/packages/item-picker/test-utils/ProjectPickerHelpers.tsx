import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {RelayEnvironmentProvider} from 'react-relay'
import React from 'react'
import type {createMockEnvironment} from 'relay-test-utils'
import {DefaultProjectPickerAnchor, ProjectPicker} from '../components/ProjectPicker'
import {noop} from '@github-ui/noop'
import type {ProjectPickerProject$data} from '../components/__generated__/ProjectPickerProject.graphql'

type MockProjectPickerProject = Omit<ProjectPickerProject$data, ' $fragmentType'>

export type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  shortcutEnabled: boolean
  readonly: boolean
  selectedProjects?: MockProjectPickerProject[]
  includeClassicProjects?: boolean
  firstSelectedProjectTitle?: string
  onSave?: () => void
}

export function TestProjectPickerComponent({
  environment,
  includeClassicProjects = false,
  ...props
}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <React.Suspense fallback="...Loading">
        <Component {...props} includeClassicProjects={includeClassicProjects} />
      </React.Suspense>
    </RelayEnvironmentProvider>
  )
}

function Component(props: Omit<TestComponentProps, 'environment'>) {
  const {selectedProjects, onSave} = props

  return (
    <ProjectPicker
      anchorElement={anchorProps => <DefaultProjectPickerAnchor {...props} anchorProps={anchorProps} />}
      pickerId={'test'}
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      selectedProjects={(selectedProjects as any) ?? []}
      onSave={onSave ?? noop}
      owner={'github'}
      repo={'issues'}
      {...props}
    />
  )
}

export function buildProject({
  title,
  closed,
  viewerCanUpdate = true,
  hasReachedItemsLimit = false,
}: {
  title: string
  closed: boolean
  viewerCanUpdate?: boolean
  hasReachedItemsLimit?: boolean
}) {
  return {
    id: mockRelayId(),
    title,
    closed,
    __typename: 'ProjectV2' as const,
    number: 123,
    url: 'memex_url',
    viewerCanUpdate,
    hasReachedItemsLimit,
  }
}
