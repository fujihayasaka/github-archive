import vulnerabilitiesExtension from '../extensions/vulnerabilities'
import {transformContentToHTML} from '../render-markdown'

describe('vulnerabilities extension', () => {
  it('Adds code vulnerability annotations', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    global.crypto.randomUUID = jest.fn(() => 'e042c512-3b61-407a-8e78-532337c5e91a') as any
    const input = `\`\`\`
    console.log('hello world')
    \`\`\`\n`
    const vulnerabilities = [
      {
        startOffset: 5,
        endOffset: 9,
        details: {
          type: 'sql-injection',
          uiType: 'SQL Injection',
          description: 'SQL injections are dangerous',
          uiDescription: 'SQL injections are dangerous',
        },
      },
    ]
    const result = transformContentToHTML(input, [vulnerabilitiesExtension({vulnerabilities})])
    const details =
      '<details class="snippet-vulnerabilities-details"><summary class="snippet-vulnerability-summary"><div class="snippet-vulnerability-shield-icon"></div>1 vulnerability detected<div class="snippet-vulnerability-chevron"></div></summary><div class="snippet-vulnerability-details"><p class="snippet-vulnerability-details-title">SQL Injection</p><p class="snippet-vulnerability-details-description">SQL injections are dangerous</p></div></details>'
    expect(result).toContain(details)
  })
})
