import {render, screen} from '@testing-library/react'

import {ActivityHeader} from '../ActivityHeader'
import type {CommentAuthorAssociation} from '../CommentActions.stories'

const baseProps = {
  comment: {
    authorAssociation: 'COLLABORATOR' as CommentAuthorAssociation,
    id: '1',
    createdAt: '2024-01-01T00:00:00Z',
    isHidden: false,
    minimizedReason: null,
    repository: {
      id: 'repo1',
      isPrivate: false,
      name: 'repo',
      owner: {login: 'owner', url: '/owner'},
    },
    url: '/some/comment/url',
  },
  commentAuthorLogin: 'octocat',
  avatarUrl: '/avatar.png',
  isMinimized: false,
}

test('renders comment.url when not outdated', () => {
  render(<ActivityHeader {...baseProps} isOutdated={false} />)
  const link = screen.getByRole('link', {name: /on/i})
  expect(link).toHaveAttribute('href', '/some/comment/url')
})

test('renders getOutdatedCommentUrl when outdated', () => {
  render(<ActivityHeader {...baseProps} isOutdated originalDiffPathUri="/some/diff/path#r123" />)
  const link = screen.getByRole('link', {name: /on/i})
  expect(link).toHaveAttribute('href', 'http://localhost/some/diff/path?new_files_changed=true#r123')
})
