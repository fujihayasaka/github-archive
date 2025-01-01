/* eslint eslint-comments/no-use: off */

import type {Meta} from '@storybook/react'

import {RepoSelectionDialog, type RepoSelectionDialogProps} from './RepoSelectionDialog'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {SearchRepositories, TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import {RelayEnvironmentProvider, type OperationDescriptor, type PreloadedQuery} from 'react-relay'
import {ComponentWithPreloadedQueryRef, mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import React from 'react'
import type {RepoData} from '@github-ui/copilot-chat/utils/copilot-chat-types'

type WrappedRepoSelectionDialogProps = {
  queryRef: PreloadedQuery<RepositoryPickerTopRepositoriesQuery>
  initialFilterText?: string
  prefferedUserLogin?: string
  onClose?: (selectedItems: RepoData[]) => void
  initialSelectedItems?: RepoData[]
  isOpen?: boolean
}

const meta = {
  title: 'CopilotChatSettings/RepoSelectionDialog',
  component: RepoSelectionDialog,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof RepoSelectionDialog>

export default meta

const defaultArgs: Partial<RepoSelectionDialogProps> = {
  initialFilterText: '',
  prefferedUserLogin: '',
  initialSelectedItems: [],
  isOpen: true,
  onClose: (selectedItems: RepoData[]) => {
    return selectedItems
  },
}

export const Default = {
  args: {
    initialFilterText: defaultArgs.initialFilterText,
    isOpen: defaultArgs.isOpen,
  },
  argTypes: {
    initialFilterText: {control: 'text'},
    isOpen: {control: 'boolean'},
  },
  render: (props: WrappedRepoSelectionDialogProps) => {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [
              {node: buildRepository({owner: 'orgA', name: 'repoA'})},
              {node: buildRepository({owner: 'orgA', name: 'repoB'})},
              {node: buildRepository({owner: 'orgB', name: 'repoC'})},
            ],
          }
        },
      })
    })

    environment.mock.queuePendingOperation(SearchRepositories, {searchQuery: 'search in:name archived:false'})
    for (let i = 0; i < 10; i++) {
      environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
        return MockPayloadGenerator.generate(operation, {
          SearchResultItemConnection() {
            return {
              nodes: [
                buildRepository({owner: 'orgB', name: 'repoA'}),
                buildRepository({owner: 'orgC', name: 'repoB'}),
                buildRepository({owner: 'orgA', name: 'repoC'}),
              ],
            }
          },
        })
      })
    }

    return (
      <RelayEnvironmentProvider environment={environment}>
        <React.Suspense fallback="...Loading">
          <ComponentWithPreloadedQueryRef
            component={WrappedRepoSelectionDialog}
            componentProps={{
              ...defaultArgs,
              ...props,
            }}
            query={TopRepositories}
            queryVariables={{topRepositoriesFirst: 10, hasIssuesEnabled: true}}
          />
        </React.Suspense>
      </RelayEnvironmentProvider>
    )
  },
}

function WrappedRepoSelectionDialog({
  initialFilterText,
  prefferedUserLogin,
  initialSelectedItems,
  isOpen,
  onClose,
}: WrappedRepoSelectionDialogProps) {
  return (
    <RepoSelectionDialog
      initialFilterText={initialFilterText}
      prefferedUserLogin={prefferedUserLogin}
      initialSelectedItems={initialSelectedItems as RepoData[]}
      isOpen={isOpen as boolean}
      onClose={onClose as (selectedItems: RepoData[]) => void}
    />
  )
}

function buildRepository({name, owner}: {name: string; owner: string}) {
  return {
    id: mockRelayId(),
    name,
    owner: {
      login: owner,
      avatarUrl: 'https://avatars.githubusercontent.com/u/87654321?v=4',
    },
    isPrivate: false,
    isArchived: false,
    nameWithOwner: `${owner}/${name}`,
    __typename: 'Repository',
  }
}
