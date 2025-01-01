import {combineRelatedTokens, mapPatchToDiffLines} from '../diff-helpers'

describe('`mapPatchToDiffLines` utility', () => {
  test('highlights full words if a letter is changed', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['-  hallo world', '+  hello world'],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: '  <span class="x x-first x-last">hallo</span> world',
        right: 1,
        text: '  hallo world',
        type: 'DELETION',
      },
      {
        left: 2,
        html: '  <span class="x x-first x-last">hello</span> world',
        right: 1,
        text: '  hello world',
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test("highlights only characters if it's a non-word character that changed", () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['-  hello world', '+  hello world!'],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: '  hello world',
        right: 1,
        text: '  hello world',
        type: 'DELETION',
      },
      {
        left: 2,
        html: '  hello world<span class="x x-first x-last">!</span>',
        right: 1,
        text: '  hello world!',
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('highlights neighboring words if multiple letters are changed', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['-  hallo werld', '+  hello world'],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: '  <span class="x x-first x-last">hallo werld</span>',
        right: 1,
        text: '  hallo werld',
        type: 'DELETION',
      },
      {
        left: 2,
        html: '  <span class="x x-first x-last">hello world</span>',
        right: 1,
        text: '  hello world',
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('skips highlights when a line removed is longer than 1024 chars (see lib/diff_line_change_marker.rb)', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: [`- ${'hello world'.repeat(700)}`, '+  hello world!'],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: ` ${'hello world'.repeat(700)}`,
        right: 1,
        text: ` ${'hello world'.repeat(700)}`,
        type: 'DELETION',
      },
      {
        left: 2,
        html: '  hello world!',
        right: 1,
        text: '  hello world!',
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('skips highlights when a line added is longer than 1024 chars (see lib/diff_line_change_marker.rb)', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['- hello world!', `+ ${'hello world'.repeat(700)}`],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: ' hello world!',
        right: 1,
        text: ' hello world!',
        type: 'DELETION',
      },
      {
        left: 2,
        html: ` ${'hello world'.repeat(700)}`,
        right: 1,
        text: ` ${'hello world'.repeat(700)}`,
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('converts a simple addition diff', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 32,
          oldLines: 6,
          newStart: 32,
          newLines: 7,
          lines: [
            '   vertical-align: middle;',
            '   // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
            "   border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 6px)' : '50%')};",
            "+  box-shadow: 0 0 0 2px ${get('colors.avatar.border')};",
            '   height: var(--avatar-size);',
            '   width: var(--avatar-size);',
            '   ${sx}',
          ],
          linedelimiters: ['\n', '\n', '\n', '\n', '\n', '\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 32,
        html: '  vertical-align: middle;',
        right: 32,
        text: '  vertical-align: middle;',
        type: 'CONTEXT',
      },
      {
        left: 33,
        html: '  // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
        right: 33,
        text: '  // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
        type: 'CONTEXT',
      },
      {
        left: 34,
        html: '  border-radius: ${props =&gt; (props.square ? &#039;clamp(4px, var(--avatar-size) - 24px, 6px)&#039; : &#039;50%&#039;)};',
        right: 34,
        text: "  border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 6px)' : '50%')};",
        type: 'CONTEXT',
      },
      {
        left: 35,
        html: '  box-shadow: 0 0 0 2px ${get(&#039;colors.avatar.border&#039;)};',
        right: 35,
        text: "  box-shadow: 0 0 0 2px ${get('colors.avatar.border')};",
        type: 'ADDITION',
      },
      {
        left: 35,
        html: '  height: var(--avatar-size);',
        right: 36,
        text: '  height: var(--avatar-size);',
        type: 'CONTEXT',
      },
      {
        left: 36,
        html: '  width: var(--avatar-size);',
        right: 37,
        text: '  width: var(--avatar-size);',
        type: 'CONTEXT',
      },
      {
        left: 37,
        html: '  ${sx}',
        right: 38,
        text: '  ${sx}',
        type: 'CONTEXT',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('adds spans around characters that changed between lines', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 32,
          oldLines: 7,
          newStart: 32,
          newLines: 7,
          lines: [
            '   vertical-align: middle;',
            '   // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
            "   border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 6px)' : '50%')};",
            "-  box-shadow: 0 0 0 1px ${get('colors.avatar.border')};",
            "+  box-shadow: 0 0 0 2px ${get('colors.avatar.border')};",
            '   height: var(--avatar-size);',
            '   width: var(--avatar-size);',
            '   ${sx}',
          ],
          linedelimiters: ['\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 32,
        html: '  vertical-align: middle;',
        right: 32,
        text: '  vertical-align: middle;',
        type: 'CONTEXT',
      },
      {
        left: 33,
        html: '  // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
        right: 33,
        text: '  // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
        type: 'CONTEXT',
      },
      {
        left: 34,
        html: '  border-radius: ${props =&gt; (props.square ? &#039;clamp(4px, var(--avatar-size) - 24px, 6px)&#039; : &#039;50%&#039;)};',
        right: 34,
        text: "  border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 6px)' : '50%')};",
        type: 'CONTEXT',
      },
      {
        left: 35,
        html: '  box-shadow: 0 0 0 <span class="x x-first x-last">1</span>px ${get(&#039;colors.avatar.border&#039;)};',
        right: 35,
        text: "  box-shadow: 0 0 0 1px ${get('colors.avatar.border')};",
        type: 'DELETION',
      },
      {
        left: 36,
        html: '  box-shadow: 0 0 0 <span class="x x-first x-last">2</span>px ${get(&#039;colors.avatar.border&#039;)};',
        right: 35,
        text: "  box-shadow: 0 0 0 2px ${get('colors.avatar.border')};",
        type: 'ADDITION',
      },
      {
        left: 36,
        html: '  height: var(--avatar-size);',
        right: 36,
        text: '  height: var(--avatar-size);',
        type: 'CONTEXT',
      },
      {
        left: 37,
        html: '  width: var(--avatar-size);',
        right: 37,
        text: '  width: var(--avatar-size);',
        type: 'CONTEXT',
      },
      {
        left: 38,
        html: '  ${sx}',
        right: 38,
        text: '  ${sx}',
        type: 'CONTEXT',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('adds spans around characters that changed between multiple changed lines', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 32,
          oldLines: 7,
          newStart: 32,
          newLines: 7,
          lines: [
            '   vertical-align: middle;',
            '   // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
            "-  border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 6px)' : '50%')};",
            "-  box-shadow: 0 0 0 1px ${get('colors.avatar.border')};",
            "+  border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 8px)' : '50%')};",
            "+  box-shadow: 0 0 0 2px ${get('colors.avatar.border')};",
            '   height: var(--avatar-size);',
            '   width: var(--avatar-size);',
            '   ${sx}',
          ],
          linedelimiters: ['\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 32,
        html: '  vertical-align: middle;',
        right: 32,
        text: '  vertical-align: middle;',
        type: 'CONTEXT',
      },
      {
        left: 33,
        html: '  // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
        right: 33,
        text: '  // If the avatar is square and size is greater than 24px (at any breakpoint), border-radius will be 6px. Otherwise, it will be 4px.',
        type: 'CONTEXT',
      },
      {
        left: 34,
        html: '  border-radius: ${props =&gt; (props.square ? &#039;clamp(4px, var(--avatar-size) - 24px, <span class="x x-first x-last">6</span>px)&#039; : &#039;50%&#039;)};',
        right: 34,
        text: "  border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 6px)' : '50%')};",
        type: 'DELETION',
      },
      {
        left: 35,
        html: '  box-shadow: 0 0 0 <span class="x x-first x-last">1</span>px ${get(&#039;colors.avatar.border&#039;)};',
        right: 34,
        text: "  box-shadow: 0 0 0 1px ${get('colors.avatar.border')};",
        type: 'DELETION',
      },
      {
        left: 36,
        html: '  border-radius: ${props =&gt; (props.square ? &#039;clamp(4px, var(--avatar-size) - 24px, <span class="x x-first x-last">8</span>px)&#039; : &#039;50%&#039;)};',
        right: 34,
        text: "  border-radius: ${props => (props.square ? 'clamp(4px, var(--avatar-size) - 24px, 8px)' : '50%')};",
        type: 'ADDITION',
      },
      {
        left: 36,
        html: '  box-shadow: 0 0 0 <span class="x x-first x-last">2</span>px ${get(&#039;colors.avatar.border&#039;)};',
        right: 35,
        text: "  box-shadow: 0 0 0 2px ${get('colors.avatar.border')};",
        type: 'ADDITION',
      },
      {
        left: 36,
        html: '  height: var(--avatar-size);',
        right: 36,
        text: '  height: var(--avatar-size);',
        type: 'CONTEXT',
      },
      {
        left: 37,
        html: '  width: var(--avatar-size);',
        right: 37,
        text: '  width: var(--avatar-size);',
        type: 'CONTEXT',
      },
      {
        left: 38,
        html: '  ${sx}',
        right: 38,
        text: '  ${sx}',
        type: 'CONTEXT',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('correctly handles html tokens for non-changed tokens on addition or deletion', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['-  bool && <MyComponent>', '+    bool && <MyComponent>'],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: '<span class="x x-first x-last">  </span>bool &amp;&amp; &lt;MyComponent&gt;',
        right: 1,
        text: '  bool && <MyComponent>',
        type: 'DELETION',
      },
      {
        left: 2,
        html: '<span class="x x-first x-last">    </span>bool &amp;&amp; &lt;MyComponent&gt;',
        right: 1,
        text: '    bool && <MyComponent>',
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('correctly handles html tokens on changed token on addition or deletion', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['-  bool && <MyComponent>', '+  bool && <NewComponent>'],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: '  bool &amp;&amp; &lt;<span class="x x-first x-last">MyComponent</span>&gt;',
        right: 1,
        text: '  bool && <MyComponent>',
        type: 'DELETION',
      },
      {
        left: 2,
        html: '  bool &amp;&amp; &lt;<span class="x x-first x-last">NewComponent</span>&gt;',
        right: 1,
        text: '  bool && <NewComponent>',
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })

  test('correctly handles html tokens on full addition, deletion, and context lines', () => {
    const patch = {
      oldFileName: 'Avatar.tsx',
      oldHeader: '',
      newFileName: 'Avatar.tsx',
      newHeader: '',
      hunks: [
        {
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['-  bool && <MyComponent>', '   const myfunction = () => {};', '+  bool && <NewComponent>'],
          linedelimiters: ['\n', '\n'],
        },
      ],
    }

    const hunkLines = [
      {
        left: 1,
        html: '  bool &amp;&amp; &lt;MyComponent&gt;',
        right: 1,
        text: '  bool && <MyComponent>',
        type: 'DELETION',
      },
      {
        left: 2,
        html: '  const myfunction = () =&gt; {};',
        right: 1,
        text: '  const myfunction = () => {};',
        type: 'CONTEXT',
      },
      {
        left: 3,
        html: '  bool &amp;&amp; &lt;NewComponent&gt;',
        right: 2,
        text: '  bool && <NewComponent>',
        type: 'ADDITION',
      },
    ]
    expect(mapPatchToDiffLines(patch)).toEqual(hunkLines)
  })
})

describe('`combineRelatedTokens` utility', () => {
  test('no-ops unless a neighboring word has a change', () => {
    const changes = [{value: 'H1llo', removed: true, added: undefined}, {value: ' world'}]
    expect(combineRelatedTokens(changes)).toEqual([
      {value: 'H1llo', removed: true, added: undefined},
      {value: ' world'},
    ])
  })

  test('combines tokens that are next to each other', () => {
    const changes = [
      {value: 'H1llo', removed: true, added: undefined},
      {value: ' '},
      {value: 'werd', removed: true, added: undefined},
    ]

    expect(combineRelatedTokens(changes)).toEqual([{value: 'H1llo werd', removed: true, added: undefined}])
  })
})
