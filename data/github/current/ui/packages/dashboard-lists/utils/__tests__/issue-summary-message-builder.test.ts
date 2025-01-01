import {buildMessages} from '../issue-summary-message-builder'

describe('buildMessages', () => {
  it('returns a message for each issue', () => {
    const issues = [
      {
        id: '1',
        title: 'Issue 1',
        description: 'Issue 1 body',
        permalink: 'issue-1-permalink',
        commentCount: 1,
        comments: [{body: 'hello', author: 'collaborator'}],
        updatedAt: '2022-01-01',
      },
      {
        id: '2',
        title: 'Issue 2',
        description: 'Issue 2 body',
        permalink: 'issue-2-permalink',
        commentCount: 2,
        comments: [{body: 'world', author: 'collaborator'}],
        updatedAt: '2022-01-01',
      },
      {
        id: '3',
        title: 'Issue 3',
        description: 'Issue 3 body',
        permalink: 'issue-3-permalink',
        commentCount: 3,
        comments: [],
        updatedAt: '2022-01-01',
      },
    ]

    const messages = buildMessages(issues, 'system prompt')
    expect(messages).toHaveLength(4)
    expect(messages).toEqual(
      expect.arrayContaining([
        {
          role: 'user',
          content: 'Title: Issue 1\n Description: Issue 1 body\n Comments: collaborator commented: hello',
        },
        {
          role: 'user',
          content: 'Title: Issue 2\n Description: Issue 2 body\n Comments: collaborator commented: world',
        },
        {
          role: 'user',
          content: 'Title: Issue 3\n Description: Issue 3 body\n Comments: ',
        },
      ]),
    )
  })

  it('builds the the system message', () => {
    const systemPrompt = 'system prompt'
    const fullPrompt = systemPrompt.concat(
      '\nReturn a JSON object with the issue titles as keys and the one-sentence summary as a value.',
    )
    const messages = buildMessages([], systemPrompt)
    expect(messages).toHaveLength(1)
    expect(messages).toEqual([{role: 'system', content: fullPrompt}])
  })
})
