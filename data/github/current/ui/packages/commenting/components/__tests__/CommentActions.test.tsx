import {mockClientEnv} from '@github-ui/client-env/mock'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {TEST_IDS} from '../../constants/test-ids'
import type {CommentActionsProps} from '../CommentActions'
import {CommentActions} from '../CommentActions'

const mockComment: CommentActionsProps['comment'] = {
  authorAssociation: 'COLLABORATOR',
  body: 'This is a comment body',
  id: '1',
  createdAt: '2023-01-01T00:00:00Z',
  isHidden: false,
  referenceText: 'Reference text',
  minimizedReason: null,
  repository: {
    id: 'repo1',
    isPrivate: false,
    name: 'repo-name',
    owner: {
      id: 'owner1',
      login: 'owner-login',
      url: 'https://github.com/owner-login',
    },
  },
  url: 'https://github.com/owner-login/repo-name/issues/1#issuecomment-1',
  viewerCanDelete: true,
  viewerCanMinimize: true,
  viewerCanSeeMinimizeButton: true,
  viewerCanSeeUnminimizeButton: true,
  viewerCanUpdate: true,
  viewerCanReport: true,
  viewerCanReportToMaintainer: true,
  viewerCanBlockFromOrg: true,
  viewerCanUnblockFromOrg: true,
  author: {
    id: 'author1',
    login: 'author-login',
  },
}

const defaultProps: CommentActionsProps = {
  comment: mockComment,
  commentAuthorLogin: 'author-login',
  editComment: jest.fn(),
  onReplySelect: jest.fn(),
  isMinimized: false,
  navigate: jest.fn(),
  hideComment: jest.fn(),
  unhideComment: jest.fn(),
  deleteComment: jest.fn(),
}

beforeEach(() => {
  mockClientEnv({
    login: 'monalisa',
  })
})

describe('CommentActions', () => {
  it('renders a menu', () => {
    render(<CommentActions {...defaultProps} />)
    expect(screen.getByTestId(TEST_IDS.commentHeaderHamburger)).toBeInTheDocument()
  })

  it('shows "Reference in a new issue" when there is a viewer', async () => {
    const {user} = render(<CommentActions {...defaultProps} />)

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    expect(screen.getByText('Reference in a new issue')).toBeInTheDocument()
  })

  it('do not show "Reference in a new issue" when there is no viewer', async () => {
    mockClientEnv({
      login: undefined,
    })
    const {user} = render(<CommentActions {...defaultProps} />)

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    expect(screen.queryByText('Reference in a new issue')).not.toBeInTheDocument()
  })

  it('shows "Quote reply" in a new issue when there is a viewer', async () => {
    const {user} = render(<CommentActions {...defaultProps} />)

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    expect(screen.getByText('Quote reply')).toBeInTheDocument()
  })

  it('do not show "Quote reply" in a new issue when there is a no viewer', async () => {
    mockClientEnv({
      login: undefined,
    })
    const {user} = render(<CommentActions {...defaultProps} />)

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    expect(screen.queryByText('Quote reply')).not.toBeInTheDocument()
  })

  it('calls editComment when Edit is selected', async () => {
    const {user} = render(<CommentActions {...defaultProps} />)

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    await user.click(screen.getByText('Edit'))

    expect(defaultProps.editComment).toHaveBeenCalled()
  })

  it('calls deleteComment when Delete is selected', async () => {
    const {user} = render(<CommentActions {...defaultProps} />)

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    await user.click(screen.getByText('Delete'))

    expect(defaultProps.deleteComment).toHaveBeenCalled()
  })

  it('calls onReplySelect with quoted text when Quote reply is selected', async () => {
    const {user} = render(<CommentActions {...defaultProps} />)

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    await user.click(screen.getByText('Quote reply'))

    expect(defaultProps.onReplySelect).toHaveBeenCalled()
  })

  it('copies link to clipboard when Copy link is selected', async () => {
    const {user} = render(<CommentActions {...defaultProps} />)

    const mockedWriteText = jest.fn()
    Object.defineProperty(navigator, 'clipboard', {
      writable: true,
      value: {writeText: mockedWriteText},
    })

    await user.click(screen.getByTestId(TEST_IDS.commentHeaderHamburger))
    await user.click(screen.getByText('Copy link'))

    expect(mockedWriteText).toHaveBeenCalledWith(mockComment.url)
  })
})
