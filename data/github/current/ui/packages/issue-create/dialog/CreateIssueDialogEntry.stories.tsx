import type {Meta} from '@storybook/react'
import {Button} from '@primer/react'
import {Suspense, useState} from 'react'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {graphql, type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {buildMockRepository} from '../__tests__/helpers'
import {getSafeConfig} from '../utils/option-config'
import {CreateIssueDialogEntry} from './CreateIssueDialogEntry'
import {VALUES} from '../constants/values'

const {environment} = createRelayMockEnvironment()

const RepositoryTemplates = graphql`
  query CreateIssueDialogEntryStoryQuery($id: ID!) @relay_test_operation {
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
      <Button onClick={() => setIsOpen(!isOpen)}>Open Dialog</Button>
      {isOpen && (
        <CreateIssueDialogEntry
          navigate={url => alert(`Navigating to ${url}`)}
          onCreateSuccess={({issue, createMore}) =>
            alert(`Issue Created (createMore:${createMore}): ${JSON.stringify(issue)}`)
          }
          onCancel={() => setIsOpen(false)}
          optionConfig={getSafeConfig({storageKeyPrefix: 'prefix'})}
          isCreateDialogOpen={isOpen}
          setIsCreateDialogOpen={setIsOpen}
        />
      )}
    </>
  )
}

const meta = {
  title: 'Shared Components/IssueCreateDialog',
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
