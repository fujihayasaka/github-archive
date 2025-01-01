import type {StylingDirectiveNode, StylingDirectivesLine} from '../../types'
import {buildCodeHTML} from '../build-code-html'

describe('buildCodeHTML', () => {
  it('converts raw text and styling directives to an html string', () => {
    const raw = `print('Hello, World!')`
    const directives = [
      {s: 0, e: 5, c: 'pl-en'}, // print
      {s: 6, e: 21, c: 'pl-s'}, // 'Hello, World!'
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en">print</span>
        (
        <span class="pl-s">&#039;Hello, World!&#039;</span>
        )
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en" data-code-text="print"></span>
        <span data-code-text="("></span>
        <span class="pl-s" data-code-text="&#039;Hello, World!&#039;"></span>
        <span data-code-text=")"></span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en">
          <span data-code-text="p"></span>
          <span data-code-text="r"></span>
          <span data-code-text="i"></span>
          <span data-code-text="n"></span>
          <span data-code-text="t"></span>
        </span>
        <span data-code-text="("></span>
        <span class="pl-s">
          <span data-code-text="&#039;"></span>
          <span data-code-text="H"></span>
          <span data-code-text="e"></span>
          <span data-code-text="l"></span>
          <span data-code-text="l"></span>
          <span data-code-text="o"></span>
          <span data-code-text=","></span>
          <span data-code-text=" "></span>
          <span data-code-text="W"></span>
          <span data-code-text="o"></span>
          <span data-code-text="r"></span>
          <span data-code-text="l"></span>
          <span data-code-text="d"></span>
          <span data-code-text="!"></span>
          <span data-code-text="&#039;"></span>
        </span>
        <span data-code-text=")"></span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters-chunked', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en">
          <span data-code-text="pr"></span>
          <span data-code-text="in"></span>
          <span data-code-text="t"></span>
        </span>
        <span data-code-text="("></span>
        <span class="pl-s">
          <span data-code-text="&#039;H"></span>
          <span data-code-text="el"></span>
          <span data-code-text="lo"></span>
          <span data-code-text=", "></span>
          <span data-code-text="Wo"></span>
          <span data-code-text="rl"></span>
          <span data-code-text="d!"></span>
          <span data-code-text="&#039;"></span>
        </span>
        <span data-code-text=")"></span>
      `),
    )
  })

  // this is the same as the first test, but with a different directive format
  // this ensures that the new format is correctly converted to the old format
  it('converts raw text and array tuple styling directives to an html string', () => {
    const raw = `print('Hello, World!')`
    const directives: StylingDirectiveNode[] = [
      [0, 5, 'pl-en'], // print
      [6, 21, 'pl-s'], // 'Hello, World!'
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en">print</span>
        (
        <span class="pl-s">&#039;Hello, World!&#039;</span>
        )
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en" data-code-text="print"></span>
        <span data-code-text="("></span>
        <span class="pl-s" data-code-text="&#039;Hello, World!&#039;"></span>
        <span data-code-text=")"></span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en">
          <span data-code-text="p"></span>
          <span data-code-text="r"></span>
          <span data-code-text="i"></span>
          <span data-code-text="n"></span>
          <span data-code-text="t"></span>
        </span>
        <span data-code-text="("></span>
        <span class="pl-s">
          <span data-code-text="&#039;"></span>
          <span data-code-text="H"></span>
          <span data-code-text="e"></span>
          <span data-code-text="l"></span>
          <span data-code-text="l"></span>
          <span data-code-text="o"></span>
          <span data-code-text=","></span>
          <span data-code-text=" "></span>
          <span data-code-text="W"></span>
          <span data-code-text="o"></span>
          <span data-code-text="r"></span>
          <span data-code-text="l"></span>
          <span data-code-text="d"></span>
          <span data-code-text="!"></span>
          <span data-code-text="&#039;"></span>
        </span>
        <span data-code-text=")"></span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters-chunked', 4, false)).toEqual(
      combineLines(`
        <span class="pl-en">
          <span data-code-text="pr"></span>
          <span data-code-text="in"></span>
          <span data-code-text="t"></span>
        </span>
        <span data-code-text="("></span>
        <span class="pl-s">
          <span data-code-text="&#039;H"></span>
          <span data-code-text="el"></span>
          <span data-code-text="lo"></span>
          <span data-code-text=", "></span>
          <span data-code-text="Wo"></span>
          <span data-code-text="rl"></span>
          <span data-code-text="d!"></span>
          <span data-code-text="&#039;"></span>
        </span>
        <span data-code-text=")"></span>
      `),
    )
  })

  it('escapes special html characters', () => {
    const raw = `<span class="pl-s">Bar &quot; baz 'test single quotes'</span>`
    const directives = [
      {s: 0, e: 1, c: 'pl-k'},
      {s: 1, e: 5, c: 'pl-ent'},
      {s: 6, e: 11, c: 'pl-c1'},
      {s: 13, e: 17, c: 'pl-s'},
      {s: 18, e: 19, c: 'pl-k'},
      {s: 54, e: 56, c: 'pl-k'},
      {s: 56, e: 60, c: 'pl-ent'},
      {s: 60, e: 61, c: 'pl-k'},
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        <span class="pl-k">&lt;</span>
        <span class="pl-ent">span</span> <span class="pl-c1">class</span>
        =&quot;
        <span class="pl-s">pl-s</span>
        &quot;
        <span class="pl-k">&gt;</span>
        Bar &amp;quot; baz &#039;test single quotes&#039;
        <span class="pl-k">&lt;/</span>
        <span class="pl-ent">span</span>
        <span class="pl-k">&gt;</span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span class="pl-k" data-code-text="&lt;"></span>
        <span class="pl-ent" data-code-text="span"></span>
        <span data-code-text=" "></span>
        <span class="pl-c1" data-code-text="class"></span>
        <span data-code-text="=&quot;"></span>
        <span class="pl-s" data-code-text="pl-s"></span>
        <span data-code-text="&quot;"></span>
        <span class="pl-k" data-code-text="&gt;"></span>
        <span data-code-text="Bar &amp;quot; baz &#039;test single quotes&#039;"></span>
        <span class="pl-k" data-code-text="&lt;/"></span>
        <span class="pl-ent" data-code-text="span"></span>
        <span class="pl-k" data-code-text="&gt;"></span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters', 4, false)).toEqual(
      combineLines(`
        <span class="pl-k">
          <span data-code-text="&lt;"></span>
        </span>
        <span class="pl-ent">
          <span data-code-text="s"></span>
          <span data-code-text="p"></span>
          <span data-code-text="a"></span>
          <span data-code-text="n"></span>
        </span>
        <span data-code-text=" "></span>
        <span class="pl-c1">
          <span data-code-text="c"></span>
          <span data-code-text="l"></span>
          <span data-code-text="a"></span>
          <span data-code-text="s"></span>
          <span data-code-text="s"></span>
        </span>
        <span data-code-text="="></span>
        <span data-code-text="&quot;"></span>
        <span class="pl-s">
          <span data-code-text="p"></span>
          <span data-code-text="l"></span>
          <span data-code-text="-"></span>
          <span data-code-text="s"></span>
        </span>
        <span data-code-text="&quot;"></span>
        <span class="pl-k">
          <span data-code-text="&gt;"></span>
        </span>
        <span data-code-text="B"></span>
        <span data-code-text="a"></span>
        <span data-code-text="r"></span>
        <span data-code-text=" "></span>
        <span data-code-text="&amp;"></span>
        <span data-code-text="q"></span>
        <span data-code-text="u"></span>
        <span data-code-text="o"></span>
        <span data-code-text="t"></span>
        <span data-code-text=";"></span>
        <span data-code-text=" "></span>
        <span data-code-text="b"></span>
        <span data-code-text="a"></span>
        <span data-code-text="z"></span>
        <span data-code-text=" "></span>
        <span data-code-text="&#039;"></span>
        <span data-code-text="t"></span>
        <span data-code-text="e"></span>
        <span data-code-text="s"></span>
        <span data-code-text="t"></span>
        <span data-code-text=" "></span>
        <span data-code-text="s"></span>
        <span data-code-text="i"></span>
        <span data-code-text="n"></span>
        <span data-code-text="g"></span>
        <span data-code-text="l"></span>
        <span data-code-text="e"></span>
        <span data-code-text=" "></span>
        <span data-code-text="q"></span>
        <span data-code-text="u"></span>
        <span data-code-text="o"></span>
        <span data-code-text="t"></span>
        <span data-code-text="e"></span>
        <span data-code-text="s"></span>
        <span data-code-text="&#039;"></span>
        <span class="pl-k">
          <span data-code-text="&lt;"></span>
          <span data-code-text="/"></span>
        </span>
        <span class="pl-ent">
          <span data-code-text="s"></span>
          <span data-code-text="p"></span>
          <span data-code-text="a"></span>
          <span data-code-text="n"></span>
        </span>
        <span class="pl-k">
          <span data-code-text="&gt;"></span>
        </span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters-chunked', 4, false)).toEqual(
      combineLines(`
        <span class="pl-k">
          <span data-code-text="&lt;"></span>
        </span>
        <span class="pl-ent">
          <span data-code-text="sp"></span>
          <span data-code-text="an"></span>
        </span>
        <span data-code-text=" "></span>
        <span class="pl-c1">
          <span data-code-text="cl"></span>
          <span data-code-text="as"></span>
          <span data-code-text="s"></span>
        </span>
        <span data-code-text="=&quot;"></span>
        <span class="pl-s">
          <span data-code-text="pl"></span>
          <span data-code-text="-s"></span>
        </span>
        <span data-code-text="&quot;"></span>
        <span class="pl-k">
          <span data-code-text="&gt;"></span>
        </span>
        <span data-code-text="Ba"></span>
        <span data-code-text="r "></span>
        <span data-code-text="&amp;q"></span>
        <span data-code-text="uo"></span>
        <span data-code-text="t;"></span>
        <span data-code-text=" b"></span>
        <span data-code-text="az"></span>
        <span data-code-text=" &#039;"></span>
        <span data-code-text="te"></span>
        <span data-code-text="st"></span>
        <span data-code-text=" s"></span>
        <span data-code-text="in"></span>
        <span data-code-text="gl"></span>
        <span data-code-text="e "></span>
        <span data-code-text="qu"></span>
        <span data-code-text="ot"></span>
        <span data-code-text="es"></span>
        <span data-code-text="&#039;"></span>
        <span class="pl-k">
          <span data-code-text="&lt;/"></span>
        </span>
        <span class="pl-ent">
          <span data-code-text="sp"></span>
          <span data-code-text="an"></span>
        </span>
        <span class="pl-k">
          <span data-code-text="&gt;"></span>
        </span>
      `),
    )
  })

  it('replaces bidirectional unicode characters', () => {
    const raw = `abc\u202Adef\u202Bghi`
    const directives: StylingDirectivesLine = [{s: 2, e: 5, c: 'pl-k'}]

    expect(buildCodeHTML(raw, directives, 'plain', 4, true)).toEqual(
      combineLines(`
        ab
        <span class="pl-k">
          c
          <span class="hidden-unicode-replacement">U+202A</span>
          d
        </span>
        ef
        <span class="hidden-unicode-replacement">U+202B</span>
        ghi
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, true)).toEqual(
      combineLines(`
        <span data-code-text="ab"></span>
        <span class="pl-k">
          <span data-code-text="c"></span>
          <span class="hidden-unicode-replacement" data-code-text="U+202A"></span>
          <span data-code-text="d"></span>
        </span>
        <span data-code-text="ef"></span>
        <span class="hidden-unicode-replacement" data-code-text="U+202B"></span>
        <span data-code-text="ghi"></span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters', 4, true)).toEqual(
      combineLines(`
        <span data-code-text="a"></span>
        <span data-code-text="b"></span>
        <span class="pl-k">
          <span data-code-text="c"></span>
          <span class="hidden-unicode-replacement" data-code-text="U+202A"></span>
          <span data-code-text="d"></span>
        </span>
        <span data-code-text="e"></span>
        <span data-code-text="f"></span>
        <span class="hidden-unicode-replacement" data-code-text="U+202B"></span>
        <span data-code-text="g"></span>
        <span data-code-text="h"></span>
        <span data-code-text="i"></span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'separated-characters-chunked', 4, true)).toEqual(
      combineLines(`
        <span data-code-text="a"></span>
        <span data-code-text="b"></span>
        <span class="pl-k">
          <span data-code-text="c"></span>
          <span class="hidden-unicode-replacement" data-code-text="U+202A"></span>
          <span data-code-text="d"></span>
        </span>
        <span data-code-text="e"></span>
        <span data-code-text="f"></span>
        <span class="hidden-unicode-replacement" data-code-text="U+202B"></span>
        <span data-code-text="g"></span>
        <span data-code-text="h"></span>
        <span data-code-text="i"></span>
      `),
    )
  })

  it('handles parents ending properly in doubly or triply nested directives', () => {
    const raw =
      '    static addMappings(Map<String, String> mappings, Map<String, Map<String, List<String>>> methods, Map<String, Map<String, String>> fields) {'
    const directives = [
      {s: 4, e: 10, c: 'pl-k'},
      {s: 11, e: 22, c: 'pl-en'},
      {s: 23, e: 42, c: 'pl-k'},
      {s: 27, e: 33, c: 'pl-k'},
      {s: 35, e: 41, c: 'pl-k'},
      {s: 43, e: 51, c: 'pl-v'},
      {s: 53, e: 91, c: 'pl-k'},
      {s: 57, e: 63, c: 'pl-k'},
      {s: 65, e: 90, c: 'pl-k'},
      {s: 69, e: 75, c: 'pl-k'},
      {s: 77, e: 89, c: 'pl-k'},
      {s: 82, e: 88, c: 'pl-k'},
      {s: 92, e: 99, c: 'pl-v'},
      {s: 101, e: 133, c: 'pl-k'},
      {s: 105, e: 111, c: 'pl-k'},
      {s: 113, e: 132, c: 'pl-k'},
      {s: 117, e: 123, c: 'pl-k'},
      {s: 125, e: 131, c: 'pl-k'},
      {s: 134, e: 140, c: 'pl-v'},
    ]
    //can't combine lines on this because it removes the whitespace
    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      `    <span class="pl-k">static</span> <span class="pl-en">addMappings</span>(<span class="pl-k">Map&lt;<span class="pl-k">String</span>, <span class="pl-k">String</span>&gt;</span> <span class="pl-v">mappings</span>, <span class="pl-k">Map&lt;<span class="pl-k">String</span>, <span class="pl-k">Map&lt;<span class="pl-k">String</span>, <span class="pl-k">List&lt;<span class="pl-k">String</span>&gt;</span>&gt;</span>&gt;</span> <span class="pl-v">methods</span>, <span class="pl-k">Map&lt;<span class="pl-k">String</span>, <span class="pl-k">Map&lt;<span class="pl-k">String</span>, <span class="pl-k">String</span>&gt;</span>&gt;</span> <span class="pl-v">fields</span>) {`,
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(
        `
        <span data-code-text="    "></span>
        <span class="pl-k" data-code-text="static"></span>
        <span data-code-text=" "></span>
        <span class="pl-en" data-code-text="addMappings"></span>
        <span data-code-text="("></span>
        <span class="pl-k">
          <span data-code-text="Map&lt;"></span>
          <span class="pl-k" data-code-text="String"></span>
          <span data-code-text=", "></span>
          <span class="pl-k" data-code-text="String"></span>
          <span data-code-text="&gt;"></span>
        </span>
        <span data-code-text=" "></span>
        <span class="pl-v" data-code-text="mappings"></span>
        <span data-code-text=", "></span>
        <span class="pl-k">
          <span data-code-text="Map&lt;"></span>
          <span class="pl-k" data-code-text="String"></span>
          <span data-code-text=", "></span>
          <span class="pl-k">
            <span data-code-text="Map&lt;"></span>
            <span class="pl-k" data-code-text="String"></span>
            <span data-code-text=", "></span>
            <span class="pl-k">
              <span data-code-text="List&lt;"></span>
              <span class="pl-k" data-code-text="String"></span>
              <span data-code-text="&gt;"></span>
            </span>
            <span data-code-text="&gt;"></span>
          </span>
          <span data-code-text="&gt;"></span>
        </span>
        <span data-code-text=" "></span>
        <span class="pl-v" data-code-text="methods"></span>
        <span data-code-text=", "></span>
        <span class="pl-k">
          <span data-code-text="Map&lt;"></span>
          <span class="pl-k" data-code-text="String"></span>
          <span data-code-text=", "></span>
          <span class="pl-k">
            <span data-code-text="Map&lt;"></span>
            <span class="pl-k" data-code-text="String"></span>
            <span data-code-text=", "></span>
            <span class="pl-k" data-code-text="String"></span>
            <span data-code-text="&gt;"></span>
          </span>
          <span data-code-text="&gt;"></span>
        </span>
        <span data-code-text=" "></span>
        <span class="pl-v" data-code-text="fields"></span>
        <span data-code-text=") {"></span>`,
      ),
    )
  })

  it('handles parents ending properly in doubly or triply nested directives (2)', () => {
    const raw = '$(C_OBJS): $(BUILD_DIR)/%.o: %.c $$(dep)'
    const directives = [
      //three layers deep
      {s: 0, e: 9, c: 'pl-en'},
      {s: 0, e: 9, c: 'pl-s'},
      {s: 0, e: 9, c: 'pl-k'},
      {s: 2, e: 8, c: 'pl-smi'},
      {s: 11, e: 23, c: 'pl-s'},
      {s: 13, e: 22, c: 'pl-smi'},
      {s: 24, e: 25, c: 'pl-c1'},
      {s: 29, e: 30, c: 'pl-c1'},
      {s: 33, e: 40, c: 'pl-s'},
      {s: 36, e: 39, c: 'pl-smi'},
    ]
    //can't combine lines on this because it removes the whitespace
    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      `<span class="pl-en"><span class="pl-s"><span class="pl-k">$(<span class="pl-smi">C_OBJS</span>)</span></span></span>: <span class="pl-s">$(<span class="pl-smi">BUILD_DIR</span>)</span>/<span class="pl-c1">%</span>.o: <span class="pl-c1">%</span>.c <span class="pl-s">$$(<span class="pl-smi">dep</span>)</span>`,
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(
        `
        <span class="pl-en">
          <span class="pl-s">
            <span class="pl-k">
              <span data-code-text="$("></span>
              <span class="pl-smi" data-code-text="C_OBJS"></span>
              <span data-code-text=")"></span>
            </span>
          </span>
        </span>
        <span data-code-text=": "></span>
        <span class="pl-s">
          <span data-code-text="$("></span>
          <span class="pl-smi" data-code-text="BUILD_DIR"></span>
          <span data-code-text=")"></span>
        </span>
        <span data-code-text="/"></span>
        <span class="pl-c1" data-code-text="%"></span>
        <span data-code-text=".o: "></span>
        <span class="pl-c1" data-code-text="%"></span>
        <span data-code-text=".c "></span>
        <span class="pl-s">
          <span data-code-text="$$("></span>
          <span class="pl-smi" data-code-text="dep"></span>
          <span data-code-text=")"></span>
        </span>`,
      ),
    )
  })

  it('handles parents ending properly in doubly nested directives', () => {
    const raw = '        *list((f"metadata_{key}") for key in APPLICATION_METADATA_FIELDS),'
    const directives = [
      {s: 8, e: 9, c: 'pl-c1'},
      {s: 9, e: 13, c: 'pl-en'},
      {s: 15, e: 32, c: 'pl-s'},
      {s: 26, e: 31, c: 'pl-s1'},
      {s: 26, e: 27, c: 'pl-k'},
      {s: 27, e: 30, c: 'pl-s1'},
      {s: 30, e: 31, c: 'pl-k'},
      {s: 34, e: 37, c: 'pl-k'},
      {s: 38, e: 41, c: 'pl-s1'},
      {s: 42, e: 44, c: 'pl-c1'},
      {s: 45, e: 72, c: 'pl-v'},
    ]
    // can't combine lines on this because it removes the leading whitespace
    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      `        <span class="pl-c1">*</span><span class="pl-en">list</span>((<span class="pl-s">f&quot;metadata_<span class="pl-s1"><span class="pl-k">{</span><span class="pl-s1">key</span><span class="pl-k">}</span></span>&quot;</span>) <span class="pl-k">for</span> <span class="pl-s1">key</span> <span class="pl-c1">in</span> <span class="pl-v">APPLICATION_METADATA_FIELDS</span>),`,
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(
        `
        <span data-code-text="        "></span>
        <span class="pl-c1" data-code-text="*"></span>
        <span class="pl-en" data-code-text="list"></span>
        <span data-code-text="(("></span>
        <span class="pl-s">
          <span data-code-text="f&quot;metadata_"></span>
          <span class="pl-s1">
            <span class="pl-k" data-code-text="{"></span>
            <span class="pl-s1" data-code-text="key"></span>
            <span class="pl-k" data-code-text="}"></span>
          </span>
          <span data-code-text="&quot;"></span>
        </span>
        <span data-code-text=") "></span>
        <span class="pl-k" data-code-text="for"></span>
        <span data-code-text=" "></span>
        <span class="pl-s1" data-code-text="key"></span>
        <span data-code-text=" "></span>
        <span class="pl-c1" data-code-text="in"></span>
        <span data-code-text=" "></span>
        <span class="pl-v" data-code-text="APPLICATION_METADATA_FIELDS"></span>
        <span data-code-text="),"></span>`,
      ),
    )
  })

  it('handles arbitrarily-nested directives', () => {
    const raw = `0123456789`
    const directives = [
      {s: 0, e: 5, c: 'pl-k'},
      {s: 0, e: 2, c: 'pl-k'},
      {s: 1, e: 2, c: 'pl-k'},
      {s: 3, e: 5, c: 'pl-k'},
      {s: 5, e: 10, c: 'pl-k'},
      {s: 7, e: 8, c: 'pl-k'},
      {s: 7, e: 8, c: 'pl-k'},
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(
        `<span class="pl-k">
          <span class="pl-k">
            0
            <span class="pl-k">1</span>
          </span>
          2
          <span class="pl-k">
            34
          </span>
        </span>
        <span class="pl-k">
          56
          <span class="pl-k">
            <span class="pl-k">
              7
            </span>
          </span>
          89
        </span>
      `,
      ),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(
        `<span class="pl-k">
          <span class="pl-k">
            <span data-code-text="0"></span>
            <span class="pl-k" data-code-text="1"></span>
          </span>
          <span data-code-text="2"></span>
          <span class="pl-k" data-code-text="34"></span>
        </span>
        <span class="pl-k">
          <span data-code-text="56"></span>
          <span class="pl-k">
            <span class="pl-k" data-code-text="7"></span>
          </span>
          <span data-code-text="89"></span>
        </span>`,
      ),
    )
  })

  it('handles nested directives where the end indices line up', () => {
    // For some SQL files (.hql, for example), treelights separately highlights the initial quote of every string.
    const raw = `'sql-string'`
    const directives = [
      {s: 0, e: 12, c: 'pl-s'}, // The whole thing
      {s: 0, e: 1, c: 'pl-pds'}, // Only the opening single-quote
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        <span class="pl-s">
          <span class="pl-pds">&#039;</span>
          sql-string&#039;
        </span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span class="pl-s">
          <span class="pl-pds" data-code-text="&#039;"></span>
          <span data-code-text="sql-string&#039;"></span>
        </span>
      `),
    )
  })

  it('includes text at the beginning and end of a nested directive', () => {
    const raw = `__(__inner__)__`
    const directives = [
      {s: 2, e: 13, c: 'pl-c'}, // (__inner__)
      {s: 5, e: 10, c: 'pl-k'}, // inner
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        __
        <span class="pl-c">
          (__
          <span class="pl-k">inner</span>
          __)
        </span>
        __
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span data-code-text="__"></span>
        <span class="pl-c">
          <span data-code-text="(__"></span>
          <span class="pl-k" data-code-text="inner"></span>
          <span data-code-text="__)"></span>
        </span>
        <span data-code-text="__"></span>
      `),
    )
  })

  it('includes text in between directives', () => {
    const raw = `left__right`
    const directives = [
      {s: 0, e: 4, c: 'pl-k'},
      {s: 6, e: 11, c: 'pl-s'},
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        <span class="pl-k">left</span>
        __
        <span class="pl-s">right</span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span class="pl-k" data-code-text="left"></span>
        <span data-code-text="__"></span>
        <span class="pl-s" data-code-text="right"></span>
      `),
    )
  })

  it('includes text after the final directive, before the end of the line', () => {
    const raw = `highlighted____`
    const directives = [{s: 0, e: 11, c: 'pl-s'}]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        <span class="pl-s">highlighted</span>
        ____
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span class="pl-s" data-code-text="highlighted"></span>
        <span data-code-text="____"></span>
      `),
    )
  })

  it('includes text at the end of a nested directive, at the appropriate level', () => {
    const raw = `                <style>\${styles}</style>`
    const directives = [
      {s: 0, e: 40, c: 'pl-s'}, // The whole line
      {s: 23, e: 32, c: 'pl-s1'}, // ${styles}
      {s: 23, e: 25, c: 'pl-k'}, // ${
      {s: 25, e: 31, c: 'pl-s1'}, // styles
      {s: 31, e: 32, c: 'pl-k'}, // }
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      combineLines(`
        <span class="pl-s">                &lt;style&gt;
          <span class="pl-s1">
            <span class="pl-k">\${</span>
            <span class="pl-s1">styles</span>
            <span class="pl-k">}</span>
          </span>
          &lt;/style&gt;
        </span>
      `),
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      combineLines(`
        <span class="pl-s">
          <span data-code-text="                &lt;style&gt;"></span>
          <span class="pl-s1">
            <span class="pl-k" data-code-text="\${"></span>
            <span class="pl-s1" data-code-text="styles"></span>
            <span class="pl-k" data-code-text="}"></span>
          </span>
          <span data-code-text="&lt;/style&gt;"></span>
        </span>
      `),
    )
  })

  it('ignores empty directives', () => {
    const raw = `    OpenBSD, Dragonfly, WebAssembly (browser), iOS, Illumos, Android, Solaris and Haiku.",`
    const directives = [
      {
        s: 0,
        e: 89,
        c: 'pl-s',
      },
      {
        s: 0,
        e: 0,
        c: 'pl-cce',
      },
    ]

    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(
      `<span class="pl-s">    OpenBSD, Dragonfly, WebAssembly (browser), iOS, Illumos, Android, Solaris and Haiku.&quot;</span>,`,
    )

    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
      `<span class="pl-s" data-code-text="    OpenBSD, Dragonfly, WebAssembly (browser), iOS, Illumos, Android, Solaris and Haiku.&quot;"></span><span data-code-text=","></span>`,
    )
  })

  it('handles plain text', () => {
    const raw = `test`
    const directives: StylingDirectivesLine = []
    expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(`test`)
    expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(`<span data-code-text="test"></span>`)
  })

  it('defaults to a newline', () => {
    const directives: StylingDirectivesLine = []
    expect(buildCodeHTML(undefined, directives, 'plain', 4, false)).toEqual(`\n`)
    expect(buildCodeHTML(undefined, directives, 'data-attribute', 4, false)).toEqual(
      `<span data-code-text="\n"></span>`,
    )
    expect(buildCodeHTML(undefined, directives, 'separated-characters', 4, false)).toEqual(
      `<span data-code-text="\n"></span>`,
    )
    expect(buildCodeHTML(undefined, directives, 'separated-characters-chunked', 4, false)).toEqual(
      `<span data-code-text="\n"></span>`,
    )

    expect(buildCodeHTML('', directives, 'plain', 4, false)).toEqual(`\n`)
    expect(buildCodeHTML('', directives, 'data-attribute', 4, false)).toEqual(`<span data-code-text="\n"></span>`)
    expect(buildCodeHTML('', directives, 'separated-characters', 4, false)).toEqual(`<span data-code-text="\n"></span>`)
    expect(buildCodeHTML('', directives, 'separated-characters-chunked', 4, false)).toEqual(
      `<span data-code-text="\n"></span>`,
    )
  })

  describe('conversion from tabs to spaces', () => {
    it('does not convert tabs to spaces when text is not hidden', () => {
      const raw = `\ttest`
      const directives: StylingDirectivesLine = []
      expect(buildCodeHTML(raw, directives, 'plain', 4, false)).toEqual(`\ttest`)
    })

    it('replaces a leading tab with the full tab width', () => {
      const raw = `\ttest`
      const directives: StylingDirectivesLine = []
      expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
        `<span data-code-text="    test"></span>`,
      )
    })

    it('handles arbitrary tab widths', () => {
      const raw = `\ttest`
      const directives: StylingDirectivesLine = []
      expect(buildCodeHTML(raw, directives, 'data-attribute', 12, false)).toEqual(
        `<span data-code-text="            test"></span>`,
      )
    })

    it('replaces a leading tab before highlighted text with the full tab width', () => {
      const raw = `\ttest`
      const directives = [{s: 1, e: 5, c: 'pl-k'}]
      expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
        combineLines(`
          <span data-code-text="    "></span>
          <span class="pl-k" data-code-text="test"></span>
        `),
      )
    })

    it('doesnt separate whitespace characters for separated-characters strategy', () => {
      const raw = `\ttest`
      const directives = [{s: 1, e: 5, c: 'pl-k'}]
      expect(buildCodeHTML(raw, directives, 'separated-characters', 4, false)).toEqual(
        combineLines(`
          <span data-code-text="    "></span>
          <span class="pl-k">
          <span data-code-text="t"></span>
          <span data-code-text="e"></span>
          <span data-code-text="s"></span>
          <span data-code-text="t"></span>
          </span>
        `),
      )
    })

    it('doesnt separate whitespace characters for separated-characters-chunked strategy', () => {
      const raw = `\ttest`
      const directives = [{s: 1, e: 5, c: 'pl-k'}]
      expect(buildCodeHTML(raw, directives, 'separated-characters-chunked', 4, false)).toEqual(
        combineLines(`
          <span data-code-text="    "></span>
          <span class="pl-k">
          <span data-code-text="te"></span>
          <span data-code-text="st"></span>
          </span>
        `),
      )
    })

    it('converts a tab following text to the remaining number of characters before the next tab stop', () => {
      const raw = `0\t1`
      const directives: StylingDirectivesLine = []
      expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(`<span data-code-text="0   1"></span>`)
    })

    it('only counts raw text characters toward the tab stop', () => {
      const raw = `0\t1`
      const directives: StylingDirectivesLine = [{s: 0, e: 1, c: 'pl-k'}]
      expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
        combineLines(`
          <span class="pl-k" data-code-text="0"></span>
          <span data-code-text="   1"></span>
        `),
      )
    })

    it('correctly calculates tab stops when there are multiple tabs', () => {
      const raw = `0\t1\t\t2`
      const directives: StylingDirectivesLine = []
      expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
        `<span data-code-text="0   1       2"></span>`,
      )
    })

    it('correctly handles multi-byte characters', () => {
      const raw = `统一码\ttext`
      const directives: StylingDirectivesLine = []
      expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
        `<span data-code-text="统一码 text"></span>`,
      )
    })

    it('correctly handles surrogate pairs', () => {
      const raw = `😀\ttext`
      const directives: StylingDirectivesLine = []
      expect(buildCodeHTML(raw, directives, 'data-attribute', 4, false)).toEqual(
        `<span data-code-text="😀   text"></span>`,
      )
    })
  })
})

function combineLines(expectedWithNewlines: string): string {
  return expectedWithNewlines.replaceAll(/\n\s+/g, '').trim()
}
