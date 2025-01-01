import publicCodeReferencesExtension from '../extensions/public-code-references'
import {transformContentToHTML} from '../render-markdown'

describe('public-code-references extension', () => {
  it('Adds public code reference annotations', () => {
    const input = `\`\`\`
    # Hello, world
    \`\`\`\n`
    const references = [
      {
        startOffset: 5,
        endOffset: 9,
        details: {
          sourceURL: 'https://github.com/monalisa/smile/tree/deadbeef/smile.md',
          language: 'markdown',
          license: 'MIT',
        },
      },
    ]
    const result = transformContentToHTML(input, [publicCodeReferencesExtension({references})])
    expect(result).toContain('github.com/monalisa/smile')
  })
})
