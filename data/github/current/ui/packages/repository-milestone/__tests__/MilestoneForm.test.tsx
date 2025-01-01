import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneForm} from '../components/MilestoneForm'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import {LABELS} from '../constants/labels'
import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'
import type {MilestoneFormTestQuery} from './__generated__/MilestoneFormTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'

type RepositoryQueryType = {
  repositoryQuery: MilestoneFormTestQuery
}

const milestoneFormQuery = graphql`
  query MilestoneFormTestQuery @relay_test_operation {
    node(id: "repo-123") {
      ... on Repository {
        # eslint-disable-next-line relay/unused-fields
        viewerCanPush
        ...MilestoneFormRepositoryQueryInternal @dangerously_unaliased_fixme
      }
    }
  }
`

const baseConfig: RelayMockProps<RepositoryQueryType> = {
  queries: {
    repositoryQuery: {
      type: 'fragment',
      query: milestoneFormQuery,
      variables: {},
    },
  },
}

describe('MilestoneForm', () => {
  const onSubmit = jest.fn()
  const onCancel = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
  })

  const defaultProps = {
    onSubmit,
    onCancel,
    formTitle: LABELS.createMilestone,
    formSubmitLabel: LABELS.createMilestone,
  }

  test('renders the milestone form', () => {
    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneForm repository={repositoryQuery.node!} {...defaultProps} />
        </Wrapper>
      ),
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              viewerCanPush: true,
            }),
          },
        },
      },
    )

    expect(screen.getByRole('heading', {level: 1, name: LABELS.createMilestone})).toBeInTheDocument()
    expect(screen.getByText(LABELS.title)).toBeInTheDocument()
    expect(screen.getByText(LABELS.dueDate)).toBeInTheDocument()
    expect(screen.getByText(LABELS.description)).toBeInTheDocument()

    expect(screen.getByRole('button', {name: LABELS.cancel})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: LABELS.createMilestone})).toBeInTheDocument()
  })

  test('displays validation error when submitting with empty title', async () => {
    const user = setupUserEvent()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneForm repository={repositoryQuery.node!} {...defaultProps} />
        </Wrapper>
      ),
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              viewerCanPush: true,
            }),
          },
        },
      },
    )

    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    expect(onSubmit).not.toHaveBeenCalled()
    expect(screen.getByText(LABELS.titleRequired)).toBeInTheDocument()
  })

  test('calls onCancel when cancel button is clicked', async () => {
    const user = setupUserEvent()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneForm repository={repositoryQuery.node!} {...defaultProps} />
        </Wrapper>
      ),
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              viewerCanPush: true,
            }),
          },
        },
      },
    )

    await user.click(screen.getByRole('button', {name: LABELS.cancel}))

    expect(onCancel).toHaveBeenCalledTimes(1)
    expect(onSubmit).not.toHaveBeenCalled()
  })

  test('submits form with valid data', async () => {
    const user = setupUserEvent()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneForm repository={repositoryQuery.node!} {...defaultProps} />
        </Wrapper>
      ),
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              viewerCanPush: true,
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.titlePlaceholder), 'Test Milestone')
    await user.type(screen.getByPlaceholderText(LABELS.descriptionPlaceholder), 'Test Description')

    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    expect(onSubmit).toHaveBeenCalledWith(
      {
        repositoryId: 'repo-123',
        title: 'Test Milestone',
        description: 'Test Description',
        dueOn: null,
      },
      expect.any(Function),
    )
  })

  test('normalizes date correctly when submitting form', async () => {
    const mockDate = new Date(2025, 4, 15)
    jest.useFakeTimers()
    jest.setSystemTime(mockDate)

    const inputLocalDate = new Date(2025, 4, 28)

    const user = setupUserEvent()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneForm
            repository={repositoryQuery.node!}
            {...defaultProps}
            initialValues={{
              dueOn: inputLocalDate.toISOString(),
            }}
          />
        </Wrapper>
      ),
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              viewerCanPush: true,
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.titlePlaceholder), 'Test Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    const expectedUTCDate = new Date(Date.UTC(2025, 4, 28)).toISOString()

    expect(onSubmit).toHaveBeenCalledWith(
      {
        repositoryId: 'repo-123',
        title: 'Test Milestone',
        description: '',
        dueOn: expectedUTCDate,
      },
      expect.any(Function),
    )

    const datePartOnly = expectedUTCDate.split('T')[0]
    expect(datePartOnly).toBe('2025-05-28')

    const timePartOnly = expectedUTCDate?.split('T')[1]?.split('.')[0]
    expect(timePartOnly).toBe('00:00:00')

    jest.useRealTimers()
    jest.resetModules()
  })
})
