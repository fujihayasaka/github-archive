import type {Meta} from '@storybook/react'
import {Button} from '@primer/react'
import {Suspense, useState} from 'react'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {graphql, type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {MockPayloadGenerator, createMockEnvironment} from 'relay-test-utils'
import {buildMockRepository} from '../__tests__/helpers'
import {VALUES} from '../constants/values'

import {CreateIssueModal} from './IssueCreateDialogWebComponent'

const RepositoryTemplates = graphql`
  query IssueCreateDialogWebComponentQuery($id: ID!) @relay_test_operation {
    node(id: $id) {
      ... on Repository {
        # eslint-disable-next-line relay/must-colocate-fragment-spreads This will be fixed once the itempickers are not using @inline
        ...RepositoryPickerRepository
        # eslint-disable-next-line relay/must-colocate-fragment-spreads This will be fixed once the itempickers are not using @inline
        ...CreateIssueDialog
      }
    }
  }
`

const environment = createMockEnvironment()

function EntryPoint() {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <Suspense fallback="...Loading">
        <TestComponent />
      </Suspense>
    </RelayEnvironmentProvider>
  )
}

function TestComponent() {
  const [isOpen, setIsOpen] = useState(false)

  return (
    <>
      <Button onClick={() => setIsOpen(!isOpen)}>Click to create a new issue</Button>
      {isOpen && <CreateIssueModal key={'1234'} />}
    </>
  )
}

const meta = {
  title: 'Shared Components/IssueCreateModal',
  component: TestComponent,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof EntryPoint>

export default meta

export const CreateIssueDialogEntryExample = {
  args: {},
  render: () => {
    const mockedRepos = [
      buildMockRepository({owner: 'orgA', name: 'repoA'}),
      buildMockRepository({owner: 'orgA', name: 'repoB'}),
      buildMockRepository({owner: 'orgB', name: 'repoC'}),
    ]

    environment.mock.queuePendingOperation(TopRepositories, {
      topRepositoriesFirst: VALUES.repositoriesPreloadCount,
      hasIssuesEnabled: true,
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [{node: mockedRepos[0]}, {node: mockedRepos[1]}, {node: mockedRepos[2]}],
          }
        },
      })
    })

    for (const repository of mockedRepos) {
      environment.mock.queuePendingOperation(RepositoryTemplates, {id: repository.id})
      environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
        return MockPayloadGenerator.generate(operation, {
          Query() {
            return {node: repository}
          },
        })
      })
    }

    return <EntryPoint />
  },
}
