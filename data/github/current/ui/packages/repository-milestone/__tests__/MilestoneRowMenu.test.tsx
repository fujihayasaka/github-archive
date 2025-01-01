import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneRowMenu} from '../MilestoneRowMenu'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import type {MilestoneRowMenuTestQuery} from './__generated__/MilestoneRowMenuTestQuery.graphql'
import {commitUpdateMilestoneMutation} from '../mutations/update-milestone-mutation'
import {commitDeleteMilestoneMutation} from '../mutations/delete-milestone-mutation'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {LABELS} from '../constants/labels'

const navigateFn = jest.fn()

let mockUseSearchParams = [new URLSearchParams(''), jest.fn()]
jest.mock('../mutations/update-milestone-mutation.ts')
jest.mock('../mutations/delete-milestone-mutation.ts')
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
    useSearchParams: () => mockUseSearchParams,
  }
})

const mockedCommitUpdateMilestoneMutation = jest.mocked(commitUpdateMilestoneMutation)
const mockedCommitDeleteMilestoneMutation = jest.mocked(commitDeleteMilestoneMutation)

beforeEach(() => {
  navigateFn.mockClear()
  mockedCommitUpdateMilestoneMutation.mockClear()
  mockedCommitDeleteMilestoneMutation.mockClear()
  mockUseSearchParams = [new URLSearchParams(''), jest.fn()]
})

const renderMilestoneRowMenu = () =>
  renderRelay<{milestoneQuery: MilestoneRowMenuTestQuery}>(
    ({queryData: {milestoneQuery}}) => (
      <Wrapper>
        <MilestoneRowMenu milestone={milestoneQuery.node!} />
      </Wrapper>
    ),
    {
      relay: {
        queries: {
          milestoneQuery: {
            type: 'fragment',
            query: graphql`
              query MilestoneRowMenuTestQuery @relay_test_operation {
                node(id: "M_123") {
                  ... on Milestone {
                    ...MilestoneRowMenu @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Milestone: () => ({
            id: 'M_123',
            state: 'OPEN',
            url: 'github.com/user/repo/milestone/123',
          }),
        },
      },
    },
  )

describe('MilestoneRowMenu', () => {
  test('renders milestone menu', () => {
    renderMilestoneRowMenu()
    expect(screen.getByLabelText('Milestone menu')).toBeInTheDocument()
  })

  test('edit callback works', async () => {
    const {user} = renderMilestoneRowMenu()

    const menuButton = screen.getByLabelText('Milestone menu')
    expect(menuButton).toBeInTheDocument()
    await user.click(menuButton)

    const entry = screen.getByText('Edit')
    expect(entry).toBeInTheDocument()
    await user.click(entry)

    expect(navigateFn).toHaveBeenCalledWith('/github.com/user/repo/milestones/123/edit')
  })

  test('close callback works', async () => {
    const {user} = renderMilestoneRowMenu()
    expect(screen.getByLabelText('Milestone menu')).toBeInTheDocument()

    const menuButton = screen.getByLabelText('Milestone menu')
    expect(menuButton).toBeInTheDocument()
    await user.click(menuButton)

    const entry = screen.getByText('Close')
    expect(entry).toBeInTheDocument()
    await user.click(entry)

    expect(mockedCommitUpdateMilestoneMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        input: {id: 'M_123', state: 'CLOSED'},
      }),
    )
  })

  test('delete callback works', async () => {
    const {user} = renderMilestoneRowMenu()

    const menuButton = screen.getByLabelText('Milestone menu')
    expect(menuButton).toBeInTheDocument()
    await user.click(menuButton)

    const entry = screen.getByText('Delete')
    expect(entry).toBeInTheDocument()
    await user.click(entry)

    const deleteButton = screen.getByText(LABELS.deleteMilestoneConfirmationButton)
    expect(deleteButton).toBeInTheDocument()
    await user.click(deleteButton)

    expect(mockedCommitDeleteMilestoneMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        input: {id: 'M_123'},
      }),
    )
  })
})
