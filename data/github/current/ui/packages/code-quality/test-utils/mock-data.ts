/* eslint eslint-comments/no-use: off */
/* eslint-disable github/unescaped-html-literal */
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {CodeQualityFileFrameProps} from '../components/CodeQualityFileFrame'
import type {RepoCodeQualityIndexResponse} from '../routes/repo-code-quality-index-route'
import type {RepoCodeQualityShowResponse} from '../routes/repo-code-quality-show-route'
import type {GetRuleFilesResponse} from '../types/get-rule-files-response'
import type {GetRuleFindingsResponse} from '../types/get-rule-findings-response'
import type {GetRuleGroupsResponse} from '../types/get-rule-groups-response'
import {Grade} from '../types/grade'
import {RuleCategory} from '../types/rule-category'
import type {RuleFile} from '../types/rule-file'
import {RuleSeverity} from '../types/rule-severity'

export function getRepoCodeQualityIndexRoutePayload(): RepoCodeQualityIndexResponse {
  return {
    owner: 'octodemo',
    repo: 'repo1',
    lastScanAt: '2025-01-01T13:20:25.947Z',
    maintainability: {
      grade: Grade.C,
      findingsCount: 123,
    },
    reliability: {
      grade: Grade.D,
      findingsCount: 456,
    },
  }
}

export function getRuleGroupsResponse(): GetRuleGroupsResponse {
  return {
    rules: [
      {
        title: 'Group 1',
        ruleId: 'rule-1',
        category: RuleCategory.Maintainability,
        severity: RuleSeverity.Warning,
        findingsCount: 10,
      },
      {
        title: 'Group 2',
        ruleId: 'rule-2',
        category: RuleCategory.Maintainability,
        severity: RuleSeverity.Error,
        findingsCount: 20,
      },
      {
        title: 'Group 3',
        ruleId: 'rule-3',
        category: RuleCategory.Reliability,
        severity: RuleSeverity.Note,
        findingsCount: 30,
      },
    ],
    prevCursor: '',
    nextCursor: '',
  }
}

export function getRuleFilesResponse(): GetRuleFilesResponse {
  return {
    files: getRuleFiles(),
  }
}

export function getRuleFiles(): RuleFile[] {
  return [
    {
      filePath: 'src/state/home-badge.tsx',
      findingsCount: 1,
    },
    {
      filePath: 'src/lib.broadcast/stub.ts',
      findingsCount: 1,
    },
    {
      filePath: 'src/lib/async/accummulate.ts',
      findingsCount: 1,
    },
    {
      filePath: 'src/screens/Search/utils.ts',
      findingsCount: 1,
    },
    {
      filePath: 'src/components/Component5.tsx',
      findingsCount: 10,
    },
    {
      filePath: 'src/state/foo.tsx',
      findingsCount: 20,
    },
  ]
}

export function getRepoCodeQualityShowRoutePayload(): RepoCodeQualityShowResponse {
  return {
    owner: 'octodemo',
    repo: 'repo1',
    ruleId: 'foo',
    ruleTitle: 'Inefficient use of ContainsKey',
    ruleDescription:
      "Testing whether a dictionary contains a value before getting it is inefficient and redundant. Use 'TryGetValue' to combine these two steps",
    ruleHelp:
      '# Inefficient use of ContainsKey\nUsing the `ContainsKey` method to check whether a dictionary contains a value before getting the value is inefficient because it performs two operations on the dictionary. It is simpler and more efficient to combine the operations using the `TryGetValue` method.\n\n\n## Recommendation\nReplace the two operations with a single call to `TryGetValue`.\n\n\n## Example\nThis code first checks whether `ip` is in the `hostnames` table, before looking up the value.\n\n\n```csharp\n// BAD: Two operations on the hostnames table.\n\nif(hostnames.ContainsKey(ip))\n  return hostnames[ip];\n\n```\nThis code performs the same function as the example above, but uses `TryGetValue`, which makes it is more efficient.\n\n\n```csharp\n// GOOD: One operation on the hostnames table.\n\nif(hostnames.TryGetValue(ip, out hostname))\n  return hostname;\n\n```\n\n## References\n* MSDN: [ContainsKey Method](https://msdn.microsoft.com/en-us/library/kw5aaea4(v=vs.110).aspx), [TryGetValue Method](https://msdn.microsoft.com/en-us/library/bb347013(v=vs.110).aspx).\n',
    ruleCategory: RuleCategory.Maintainability,
    ruleSeverity: RuleSeverity.Warning,
    lastScanAt: '2025-01-01T13:20:25.947Z',
    fileCount: 2,
  }
}

export function getRuleFindingsResponse(): GetRuleFindingsResponse {
  return {
    ruleFindings: [
      {
        filePath: 'src/Component1.tsx',
        startLine: 1,
        endLine: 2,
        startColumn: 1,
        endColumn: 10,
        snippetStartLine: 1,
        codeSnippetLines: ['const foo = bar' as SafeHTMLString],
      },
      {
        filePath: 'src/Component2.tsx',
        startLine: 10,
        endLine: 11,
        startColumn: 1,
        endColumn: 10,
        snippetStartLine: 10,
        codeSnippetLines: ["console.log('Hello World')" as SafeHTMLString],
      },
      {
        filePath: 'src/SecondComponent.tsx',
        startLine: 20,
        endLine: 21,
        startColumn: 1,
        endColumn: 10,
        snippetStartLine: 17,
        codeSnippetLines: ['const bar = foo' as SafeHTMLString],
      },
    ],
    findingsCount: 3,
    prevCursor: '',
    nextCursor: '',
  }
}

export function getCodeQualityFileFrameProps(): CodeQualityFileFrameProps {
  return {
    filePath: 'src/Component1.tsx',
    snippetStartLine: 10,
    startLine: 12,
    endLine: 13,
    startColumn: 5,
    endColumn: 10,
    codeSnippetLines: [
      '<span class=pl-c>// This function represents a function that calculates the days between days</span>' as SafeHTMLString,
      '<span class=pl-k>function</span> <span class=pl-en>calculateDaysBetweenDates</span><span class=pl-kos>(</span><span class=pl-s1>begin</span><span class=pl-kos>,</span> <span class=pl-s1>end</span><span class=pl-kos>)</span> <span class=pl-kos>{</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>oneDay</span> <span class=pl-c1>=</span> <span class=pl-c1>24</span><span class=pl-c1>*</span><span class=pl-c1>60</span><span class=pl-c1>*</span><span class=pl-c1>60</span><span class=pl-c1>*</span><span class=pl-c1>1000</span><span class=pl-kos>;</span> <span class=pl-c>// hours*minutes*seconds*milliseconds</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>firstDate</span> <span class=pl-c1>=</span> <span class=pl-k>new</span> <span class=pl-v>Date</span><span class=pl-kos>(</span><span class=pl-s1>begin</span><span class=pl-kos>)</span><span class=pl-kos>;</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>secondDate</span> <span class=pl-c1>=</span> <span class=pl-k>new</span> <span class=pl-v>Date</span><span class=pl-kos>(</span><span class=pl-s1>end</span><span class=pl-kos>)</span><span class=pl-kos>;</span>' as SafeHTMLString,
      '<span class=pl-kos>}</span>' as SafeHTMLString,
    ],
  }
}

export function getCodeQualityFileFramePropsWithOverflowingLines(): CodeQualityFileFrameProps {
  return {
    ...getCodeQualityFileFrameProps(),
    codeSnippetLines: [
      '<span class=pl-c>// Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. Aenean massa. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Donec quam felis, ultricies nec, pellentesque eu, pretium quis, sem. Nulla consequat massa quis enim. Donec pede justo, fringilla vel, aliquet nec, vulputate</span>' as SafeHTMLString,
      '<span class=pl-k>function</span> <span class=pl-en>calculateDaysBetweenDates</span><span class=pl-kos>(</span><span class=pl-s1>begin</span><span class=pl-kos>,</span> <span class=pl-s1>end</span><span class=pl-kos>)</span> <span class=pl-kos>{</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>oneDay</span> <span class=pl-c1>=</span> <span class=pl-c1>24</span><span class=pl-c1>*</span><span class=pl-c1>60</span><span class=pl-c1>*</span><span class=pl-c1>60</span><span class=pl-c1>*</span><span class=pl-c1>1000</span><span class=pl-kos>;</span> <span class=pl-c>// hours*minutes*seconds*milliseconds</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>firstDate</span> <span class=pl-c1>=</span> <span class=pl-k>new</span> <span class=pl-v>Date</span><span class=pl-kos>(</span><span class=pl-s1>begin</span><span class=pl-kos>)</span><span class=pl-kos>;</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>secondDate</span> <span class=pl-c1>=</span> <span class=pl-k>new</span> <span class=pl-v>Date</span><span class=pl-kos>(</span><span class=pl-s1>end</span><span class=pl-kos>)</span><span class=pl-kos>;</span>' as SafeHTMLString,
      '<span class=pl-kos>}</span>' as SafeHTMLString,
    ],
  }
}
