/* eslint eslint-comments/no-use: off */
/* eslint-disable github/unescaped-html-literal */
import type {Meta} from '@storybook/react'
import {CodeQualityFileFrame, type CodeQualityFileFrameProps} from '../CodeQualityFileFrame'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {
  getCodeQualityFileFrameProps,
  getCodeQualityFileFramePropsWithOverflowingLines,
} from '../../test-utils/mock-data'

const meta = {
  title: 'Apps/Code Quality/CodeQualityFileFrame',
  component: CodeQualityFileFrame,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof CodeQualityFileFrame>

export default meta

export const Default = {
  args: getCodeQualityFileFrameProps(),
  render: (args: CodeQualityFileFrameProps) => <CodeQualityFileFrame {...args} />,
}

export const OverflowingLines = {
  args: {
    ...getCodeQualityFileFramePropsWithOverflowingLines(),
    codeSnippetLines: [
      '<span class=pl-c>// Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. Aenean massa. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Donec quam felis, ultricies nec, pellentesque eu, pretium quis, sem. Nulla consequat massa quis enim. Donec pede justo, fringilla vel, aliquet nec, vulputate</span>' as SafeHTMLString,
      '<span class=pl-k>function</span> <span class=pl-en>calculateDaysBetweenDates</span><span class=pl-kos>(</span><span class=pl-s1>begin</span><span class=pl-kos>,</span> <span class=pl-s1>end</span><span class=pl-kos>)</span> <span class=pl-kos>{</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>oneDay</span> <span class=pl-c1>=</span> <span class=pl-c1>24</span><span class=pl-c1>*</span><span class=pl-c1>60</span><span class=pl-c1>*</span><span class=pl-c1>60</span><span class=pl-c1>*</span><span class=pl-c1>1000</span><span class=pl-kos>;</span> <span class=pl-c>// hours*minutes*seconds*milliseconds</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>firstDate</span> <span class=pl-c1>=</span> <span class=pl-k>new</span> <span class=pl-v>Date</span><span class=pl-kos>(</span><span class=pl-s1>begin</span><span class=pl-kos>)</span><span class=pl-kos>;</span>' as SafeHTMLString,
      '    <span class=pl-k>var</span> <span class=pl-s1>secondDate</span> <span class=pl-c1>=</span> <span class=pl-k>new</span> <span class=pl-v>Date</span><span class=pl-kos>(</span><span class=pl-s1>end</span><span class=pl-kos>)</span><span class=pl-kos>;</span>' as SafeHTMLString,
      '<span class=pl-kos>}</span>' as SafeHTMLString,
    ],
  },
}
