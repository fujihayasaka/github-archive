import {Suspense, useRef} from 'react'
import {graphql, RelayEnvironmentProvider, useLazyLoadQuery} from 'react-relay'
import type {createMockEnvironment} from 'relay-test-utils'
import type {RepositoryMilestoneTestComponentQuery} from './__generated__/RepositoryMilestoneTestComponentQuery.graphql'
import {RepositoryMilestoneInternal} from '../RepositoryMilestone'

interface TestComponentProps {
  environment: ReturnType<typeof createMockEnvironment>
}

const TestQuery = graphql`
  query RepositoryMilestoneTestComponentQuery @relay_test_operation {
    repository: node(id: "mockRepoId1") {
      ... on Repository {
        ...RepositoryMilestoneInternal @dangerously_unaliased_fixme @arguments(first: 10, number: 1, query: "")
      }
    }
  }
`

export function TestComponentRoot({environment, ...rest}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <TestComponent environment={environment} {...rest} />
    </RelayEnvironmentProvider>
  )
}

export function TestComponent({environment}: TestComponentProps) {
  return (
    <Suspense fallback="...Loading">
      <TestComponentWithQuery environment={environment} />
    </Suspense>
  )
}

// eslint-disable-next-line unused-imports/no-unused-vars
const TestComponentWithQuery = ({environment}: TestComponentProps) => {
  const data = useLazyLoadQuery<RepositoryMilestoneTestComponentQuery>(TestQuery, {})

  const containerRef = useRef<HTMLDivElement>(null)

  if (!data.repository) {
    return null
  }

  return (
    <div ref={containerRef}>
      <RepositoryMilestoneInternal repository={data.repository} />
    </div>
  )
}
