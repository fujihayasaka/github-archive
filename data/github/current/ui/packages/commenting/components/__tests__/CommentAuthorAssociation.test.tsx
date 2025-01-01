import {render, screen} from '@testing-library/react'

import {TEST_IDS} from '../../constants/test-ids'
import {CommentAuthorAssociation, type CommentAuthorAssociationProps} from '../CommentAuthorAssociation'

const setup = (props: Partial<CommentAuthorAssociationProps> = {}) => {
  render(
    <CommentAuthorAssociation association="MEMBER" viewerDidAuthor={false} org="github" repo="copilot" {...props} />,
  )
}

test('when viewer a member', () => {
  setup({viewerDidAuthor: false, association: 'MEMBER'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('Member')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'This user is a member of the github organization.',
  )
})

test('when viewer is an author and member', () => {
  setup({viewerDidAuthor: true, association: 'MEMBER'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('Member')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'You are a member of the github organization.',
  )
})

test('when viewer is the owner', () => {
  setup({association: 'OWNER'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('Owner')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'This user is the owner of the copilot repository.',
  )
})

test('when viewer is the owner and a member', () => {
  setup({viewerDidAuthor: true, association: 'OWNER'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('Owner')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'You are the owner of the copilot repository.',
  )
})

// MANNEQUIN
test('when viewer is a mannequin', () => {
  setup({association: 'MANNEQUIN'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('Mannequin')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'This is a mannequin user.',
  )
})

// Collaborator
test('when viewer is a collaborator', () => {
  setup({association: 'COLLABORATOR'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('Collaborator')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'This user has been invited to collaborate on the copilot repository.',
  )
})

test('when viewer is a collaborator and a member', () => {
  setup({viewerDidAuthor: true, association: 'COLLABORATOR'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('Collaborator')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'You have been invited to collaborate on the copilot repository.',
  )
})

// FIRST_TIME_CONTRIBUTOR
test('when viewer is a first time contributor', () => {
  setup({association: 'FIRST_TIME_CONTRIBUTOR'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('First-time contributor')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'This user is a first-time contributor to the copilot repository.',
  )
})

test('when viewer is a first time contributor and a member', () => {
  setup({viewerDidAuthor: true, association: 'FIRST_TIME_CONTRIBUTOR'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('First-time contributor')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'You are a first-time contributor to the copilot repository.',
  )
})

// FIRST_TIMER
test('when viewer is a first timer', () => {
  setup({association: 'FIRST_TIMER'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('First-time GitHub contributor')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    "This user's first pull request on GitHub.",
  )
})

test('when viewer is a first timer and a member', () => {
  setup({viewerDidAuthor: true, association: 'FIRST_TIMER'})

  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveTextContent('First-time GitHub contributor')
  expect(screen.getByTestId(TEST_IDS.commentAuthorAssociation)).toHaveAttribute(
    'aria-label',
    'This is your first pull request on GitHub.',
  )
})

// NONE
test('when association is none', () => {
  setup({association: 'NONE'})

  expect(screen.queryByTestId(TEST_IDS.commentAuthorAssociation)).not.toBeInTheDocument()
})
