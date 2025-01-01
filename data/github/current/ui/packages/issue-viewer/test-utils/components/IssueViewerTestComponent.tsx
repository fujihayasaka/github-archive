import {render, Wrapper} from '@github-ui/react-core/test-utils'
import {
  graphql,
  useLazyLoadQuery,
  RelayEnvironmentProvider,
  useQueryLoader,
  usePreloadedQuery,
  type PreloadedQuery,
  useFragment,
} from 'react-relay'

import {Suspense, useEffect, useRef} from 'react'
import type {OperationDescriptor} from 'relay-runtime'
import {MockPayloadGenerator, type createMockEnvironment} from 'relay-test-utils'

import {IssueViewerContextProvider} from '../../contexts/IssueViewerContext'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import type {IssueViewerTestComponentQuery} from './__generated__/IssueViewerTestComponentQuery.graphql'
import {IssueViewerInternalFragment, IssueViewerSecondaryIssueDataFragment} from '../../components/IssueViewer'
import {generateMockPayloadWithDefaults} from '../DefaultWrappers'
import type {OptionConfig} from '../../components/OptionConfig'
import type {IssueViewerTestComponentSecondaryQuery} from './__generated__/IssueViewerTestComponentSecondaryQuery.graphql'
import type {
  IssueViewerSecondaryIssueData$data,
  IssueViewerSecondaryIssueData$key,
} from '../../components/__generated__/IssueViewerSecondaryIssueData.graphql'
import {act} from '@testing-library/react'
import type {
  IssueViewerSecondaryViewQueryRepoData$data,
  IssueViewerSecondaryViewQueryRepoData$key,
} from '../../components/__generated__/IssueViewerSecondaryViewQueryRepoData.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import {IssueViewerSecondaryViewQueryFragment} from '../../components/IssueViewerSecondaryView'
import {CommentEditsContextProvider} from '@github-ui/commenting/CommentEditsContext'
import {InputElementActiveContextProvider} from '../../contexts/InputElementActiveContext'
import {SubIssueStateProvider} from '@github-ui/sub-issues/SubIssueStateContext'
import type {IssueViewerTestComponentViewerTestQuery} from './__generated__/IssueViewerTestComponentViewerTestQuery.graphql'
import type {IssueViewerTestComponentSecondaryTestQuery} from './__generated__/IssueViewerTestComponentSecondaryTestQuery.graphql'

interface TestComponentProps {
  environment: ReturnType<typeof createMockEnvironment>
  viewerOptions?: Partial<OptionConfig>
  isViewerLoggedIn?: boolean
  secondaryIssueData?: IssueViewerSecondaryIssueData$data
  secondaryRepoData?: IssueViewerSecondaryViewQueryRepoData$data
}

type ComponentInternalProps = TestComponentProps & {
  queryRef: PreloadedQuery<IssueViewerTestComponentSecondaryQuery>
}

type ComponentFetchedProps = TestComponentProps & {
  issueKey: IssueViewerSecondaryIssueData$key
}

const IssueViewerTestSecondaryQuery = graphql`
  query IssueViewerTestComponentSecondaryQuery($issueId: ID!) @relay_test_operation {
    node(id: $issueId) {
      ... on Issue {
        ...IssueViewerSecondaryIssueData @dangerously_unaliased_fixme
      }
    }
  }
`

const IssueViewerTestQuery = graphql`
  query IssueViewerTestComponentQuery @relay_test_operation {
    issue: node(id: "mockIssueId1") {
      ... on Issue {
        ...IssueViewerIssue @dangerously_unaliased_fixme @arguments
      }
    }
    viewer: node(id: "test-id-viewer") {
      ... on User {
        ...IssueViewerViewer @dangerously_unaliased_fixme
      }
    }
  }
`

function TestComponentWithSecondaryRoot({environment, ...rest}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <TestComponentWithSecondaryQuery environment={environment} {...rest} />
    </RelayEnvironmentProvider>
  )
}

export function TestComponentRoot({environment, ...rest}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <TestComponent environment={environment} {...rest} />
    </RelayEnvironmentProvider>
  )
}

function TestComponentWithSecondaryQuery({...props}: TestComponentProps) {
  const [queryRef, loadQuery, disposeQuery] =
    useQueryLoader<IssueViewerTestComponentSecondaryQuery>(IssueViewerTestSecondaryQuery)

  useEffect(() => {
    loadQuery({issueId: 'mockIssueId1'})
    return () => {
      disposeQuery()
    }
  }, [loadQuery, disposeQuery])
  if (!queryRef) return <TestComponent {...props} />

  return <TestComponentWithSecondaryQueryInternal queryRef={queryRef} {...props} />
}

function TestComponentWithSecondaryQueryInternal({queryRef, ...rest}: ComponentInternalProps) {
  const data = usePreloadedQuery(IssueViewerTestSecondaryQuery, queryRef)

  if (!data.node) return <TestComponent {...rest} />

  return <TestComponentWithSecondaryQueryFetched issueKey={data.node} {...rest} />
}

function TestComponentWithSecondaryQueryFetched({issueKey, ...rest}: ComponentFetchedProps) {
  const data = useFragment(IssueViewerSecondaryIssueDataFragment, issueKey)

  return <TestComponent secondaryIssueData={data} {...rest} />
}

const TestComponentWithQuery = ({
  viewerOptions,
  secondaryIssueData,
  secondaryRepoData,
  isViewerLoggedIn,
}: TestComponentProps) => {
  const data = useLazyLoadQuery<IssueViewerTestComponentQuery>(IssueViewerTestQuery, {})

  const containerRef = useRef<HTMLDivElement>(null)

  if (!data.issue) {
    return null
  }

  return (
    <div ref={containerRef}>
      <IssueViewerInternalFragment
        viewerFragment={data.viewer && isViewerLoggedIn ? data.viewer : null}
        issueFragment={data.issue}
        optionConfig={{
          singleKeyShortcutsEnabled: true,
          navigate: (url: string) => {
            alert(url)
          },
          ...viewerOptions,
        }}
        containerRef={containerRef}
        secondaryIssueData={secondaryIssueData}
        secondaryRepoData={secondaryRepoData}
      />
    </div>
  )
}

export function TestComponent({
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  viewerOptions = {},
  secondaryIssueData,
  secondaryRepoData,
  isViewerLoggedIn,
  environment,
}: TestComponentProps) {
  return (
    <IssueViewerContextProvider>
      <Suspense fallback="...Loading">
        <TestComponentWithQuery
          environment={environment}
          viewerOptions={viewerOptions}
          secondaryIssueData={secondaryIssueData}
          secondaryRepoData={secondaryRepoData}
          isViewerLoggedIn={isViewerLoggedIn}
        />
      </Suspense>
    </IssueViewerContextProvider>
  )
}

export function MockRepo(
  repositoryId: string | undefined = 'test-repo',
  ownerId: string | undefined = 'test-owner',
  ownerLogin: string | undefined = 'test-owner',
) {
  return {
    id: repositoryId,
    name: 'test-repo',
    nameWithOwner: `${ownerLogin}/test-repo`,
    owner: {
      __typename: 'User',
      id: ownerId,
      login: ownerLogin,
      url: `/${ownerLogin}`,
    },
    isPrivate: false,
    databaseId: 42,
    viewerCanInteract: true,
    viewerInteractionLimitReasonHTML: '',
    planFeatures: {
      maximumAssignees: 10,
    },
  }
}

type setupMockEnvironmentProps = {
  mockOverwrites?: Record<string, () => object>
  mockSecondaryOverwrites?: Record<string, () => object>
  viewerOptions?: Partial<OptionConfig>
  isViewerLoggedIn?: boolean
}
export async function setupMockEnvironment(
  {mockOverwrites, mockSecondaryOverwrites, viewerOptions, isViewerLoggedIn = true}: setupMockEnvironmentProps = {
    mockOverwrites: {},
    mockSecondaryOverwrites: {},
    viewerOptions: {},
  },
) {
  const {environment} = createRelayMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.fragment.node.name).toBe('IssueViewerTestComponentQuery')
    const payload = generateMockPayloadWithDefaults(operation, {
      ...mockOverwrites,
      Repository() {
        return MockRepo()
      },
    })
    return payload
  })

  // This is required or we'll get the error 'Not implemented: window.scrollTo'
  Object.defineProperty(window, 'scrollTo', {value: () => {}, writable: true})
  const {container, rerender, user} = render(
    <TestComponentWithSecondaryRoot
      environment={environment}
      viewerOptions={viewerOptions}
      isViewerLoggedIn={isViewerLoggedIn}
    />,
  )

  await act(async () => {
    environment.mock.resolveMostRecentOperation((operation: OperationDescriptor) => {
      expect(operation.fragment.node.name).toBe('IssueViewerTestComponentSecondaryQuery')
      return MockPayloadGenerator.generate(operation, {
        Repository() {
          return MockRepo()
        },
        ...mockSecondaryOverwrites,
      })
    })
  })

  return {container, rerender, environment, user}
}

export function renderIssueViewerTestComponent({mockResolversIssueOverrides = {}, mockResolversRepoOverrides = {}}) {
  return renderRelay<{
    issueViewerViewTestQuery: IssueViewerTestComponentViewerTestQuery
    issueViewerViewSecondaryTestQuery: IssueViewerTestComponentSecondaryTestQuery
  }>(
    ({queryData}) => {
      const containerRef = useRef<HTMLDivElement>(null)

      const secondaryIssueData = useFragment<IssueViewerSecondaryIssueData$key>(
        IssueViewerSecondaryIssueDataFragment,
        queryData.issueViewerViewSecondaryTestQuery.repository!.issue!,
      )

      const secondaryRepoData = useFragment<IssueViewerSecondaryViewQueryRepoData$key>(
        IssueViewerSecondaryViewQueryFragment,
        queryData.issueViewerViewSecondaryTestQuery.repository!,
      )

      return (
        <CommentEditsContextProvider>
          <InputElementActiveContextProvider>
            <SubIssueStateProvider>
              <IssueViewerInternalFragment
                optionConfig={{
                  singleKeyShortcutsEnabled: true,
                  navigate: (url: string) => {
                    alert(url)
                  },
                }}
                viewerFragment={queryData.issueViewerViewTestQuery.safeViewer!}
                issueFragment={queryData.issueViewerViewTestQuery.repository!.issue!}
                containerRef={containerRef}
                isRepoOwnerEnterpriseManaged={queryData.issueViewerViewTestQuery.repository!.isOwnerEnterpriseManaged}
                secondaryIssueData={secondaryIssueData}
                secondaryRepoData={secondaryRepoData}
              />
            </SubIssueStateProvider>
          </InputElementActiveContextProvider>
        </CommentEditsContextProvider>
      )
    },
    {
      relay: {
        queries: {
          issueViewerViewTestQuery: {
            type: 'fragment',
            query: graphql`
              query IssueViewerTestComponentViewerTestQuery @relay_test_operation {
                repository(name: "repo", owner: "owner") {
                  isOwnerEnterpriseManaged
                  issue(number: 33) {
                    ...IssueViewerIssue
                  }
                }
                safeViewer {
                  ...IssueViewerViewer
                }
              }
            `,
            variables: {},
          },
          issueViewerViewSecondaryTestQuery: {
            type: 'fragment',
            query: graphql`
              query IssueViewerTestComponentSecondaryTestQuery @relay_test_operation {
                repository(name: "repo", owner: "owner") {
                  ...IssueViewerSecondaryViewQueryRepoData
                  issue(number: 10) {
                    ...IssueViewerSecondaryIssueData
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              viewerCanLabel: true,
              viewerCanSetMilestone: true,
              viewerCanUpdateMetadata: true,
              viewerCanAssign: true,
              ...mockResolversIssueOverrides,
            }
          },
          Repository() {
            return {
              planFeatures: {
                maximumAssignees: 10,
              },
              ...mockResolversRepoOverrides,
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )
}
