// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {type DraftIssueReference, NullMessageId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import isEqual from 'lodash-es/isEqual'

import {type DraftIssue, makeReferenceFromVersionedItem, makeVersionedItemFromReference} from '../content-preview-types'

const draftIssue: DraftIssue = {
  tag: 'fix-a-bug',
  id: 'new-issue:fix-a-bug#123',
  type: 'new-issue',
  name: 'Issue Title',
  body: 'Issue Description',
  repository: 'orgA/repoA',
  template: 'bug.yml',
  messageId: '321',
  isUserEdited: false,
  isStreaming: false,
  issueType: 'bug',
  assignees: [],
  labels: [],
  projects: [],
}

const draftIssueRef: DraftIssueReference = {
  tag: 'fix-a-bug',
  parentTag: undefined,
  type: 'draft-issue',
  title: 'Issue Title',
  description: 'Issue Description',
  repository: 'orgA/repoA',
  template: 'bug.yml',
  assignees: [],
  labels: [],
  projects: [],
  issueType: 'bug',
  milestone: undefined,
}

describe('makeVersionedItemFromReference', () => {
  it('makes draft issue from reference', () => {
    const output = makeVersionedItemFromReference({ref: draftIssueRef, messageIndex: 123, messageId: '321'})

    let property: keyof typeof output
    for (property in output) {
      expect(isEqual(output[property], draftIssue[property])).toBe(true)
    }
  })

  it('makes user edited draft issue from reference if no message id provided', () => {
    const output = makeVersionedItemFromReference({ref: draftIssueRef, messageIndex: 123, messageId: NullMessageId})

    expect(output.isUserEdited).toBe(true)
    expect(output.messageId).toBe(NullMessageId)
  })
})

describe('makeReferenceFromVersionedItem', () => {
  it('makes reference from draft issue', () => {
    const output = makeReferenceFromVersionedItem(draftIssue)

    let property: keyof typeof output
    for (property in output) {
      expect(isEqual(output[property], draftIssueRef[property])).toBe(true)
    }
  })
})
