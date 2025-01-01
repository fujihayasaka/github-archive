import type {SafeHTMLString} from '@github-ui/safe-html'
// eslint-disable-next-line no-restricted-imports
import ToastContext, {useToastContext} from '@github-ui/toast/ToastContext'
import type {Meta, StoryObj} from '@storybook/react'
import type React from 'react'

import {IssueMarkdownViewer} from './IssueMarkdownViewer'

// Wrap component with necessary providers
const IssueMarkdownViewerWithProviders = (props: React.ComponentProps<typeof IssueMarkdownViewer>) => {
  const toastContext = useToastContext()

  return (
    <ToastContext.Provider value={toastContext}>
      <IssueMarkdownViewer {...props} />
    </ToastContext.Provider>
  )
}

const meta = {
  title: 'Commenting/IssueMarkdownViewer',
  component: IssueMarkdownViewerWithProviders,
  parameters: {
    controls: {expanded: true},
    layout: 'padded',
  },
  tags: ['autodocs'],
  argTypes: {
    onSave: {action: 'onSave'},
    onLinkClick: {action: 'onLinkClick'},
    onConvertToIssue: {action: 'onConvertToIssue'},
    onConvertToSubIssue: {action: 'onConvertToSubIssue'},
  },
  decorators: [
    Story => (
      <div className="color-bg-default p-3" style={{maxWidth: '700px'}}>
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof IssueMarkdownViewerWithProviders>

export default meta
type Story = StoryObj<typeof meta>

// Basic markdown content for stories
const simpleMarkdown = `
# Heading 1
## Heading 2

This is a paragraph with **bold** and *italic* text.

- List item 1
- List item 2
- List item 3

[Link to GitHub](https://github.com)

> This is a blockquote

\`\`\`jsx
// Code block
function Example() {
  return <div>Hello World</div>
}
\`\`\`

| Table | Header |
| ----- | ------ |
| Cell  | Cell   |
| Cell  | Cell   |
`

// HTML representation of the markdown
const simpleHtml = `
<h1>Heading 1</h1>
<h2>Heading 2</h2>

<p>This is a paragraph with <strong>bold</strong> and <em>italic</em> text.</p>

<ul>
<li>List item 1</li>
<li>List item 2</li>
<li>List item 3</li>
</ul>

<p><a href="https://github.com">Link to GitHub</a></p>

<blockquote>
<p>This is a blockquote</p>
</blockquote>

<div class="highlight highlight-source-js">
<pre><span class="pl-c">// Code block</span>
<span class="pl-k">function</span> <span class="pl-en">Example</span>() {
  <span class="pl-k">return</span> <span class="pl-c1">&lt;</span>div<span class="pl-c1">&gt;</span>Hello World<span class="pl-c1">&lt;</span><span class="pl-c1">/</span>div<span class="pl-c1">&gt;</span>
}</pre>
</div>

<table>
<thead>
<tr>
<th>Table</th>
<th>Header</th>
</tr>
</thead>
<tbody>
<tr>
<td>Cell</td>
<td>Cell</td>
</tr>
<tr>
<td>Cell</td>
<td>Cell</td>
</tr>
</tbody>
</table>
` as SafeHTMLString

export const Default: Story = {
  args: {
    html: simpleHtml,
    markdown: simpleMarkdown,
    viewerCanUpdate: false,
    onSave: (newBody, onCompleted, _) => {
      setTimeout(() => {
        onCompleted()
      }, 1000)
    },
  },
}

export const Empty: Story = {
  args: {
    html: '' as SafeHTMLString,
    markdown: '',
    viewerCanUpdate: false,
    onSave: (newBody, onCompleted, _) => {
      setTimeout(() => {
        onCompleted()
      }, 1000)
    },
  },
  parameters: {
    docs: {
      description: {
        story: 'Shows the empty state with the "No description provided" message.',
      },
    },
  },
}

export const WithComplexContent: Story = {
  args: {
    html: `
      <h1>Project Status Update</h1>
      <p>We've made significant progress on the accessibility improvements:</p>
      <ul>
        <li>✅ ARIA attributes added to all interactive elements</li>
        <li>✅ Color contrast issues fixed</li>
        <li>⏳ Keyboard navigation improvements in progress</li>
        <li>📝 Screen reader testing scheduled for next week</li>
      </ul>
      <h2>Performance Metrics</h2>
      <table>
        <thead>
          <tr>
            <th>Metric</th>
            <th>Before</th>
            <th>After</th>
            <th>Improvement</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>First Contentful Paint</td>
            <td>1.8s</td>
            <td>0.9s</td>
            <td>50%</td>
          </tr>
          <tr>
            <td>Time to Interactive</td>
            <td>5.2s</td>
            <td>2.8s</td>
            <td>46%</td>
          </tr>
        </tbody>
      </table>
      <p>cc: @octocat @monalisa</p>
    ` as SafeHTMLString,
    markdown: `# Project Status Update
We've made significant progress on the accessibility improvements:

- ✅ ARIA attributes added to all interactive elements
- ✅ Color contrast issues fixed
- ⏳ Keyboard navigation improvements in progress
- 📝 Screen reader testing scheduled for next week

## Performance Metrics

| Metric | Before | After | Improvement |
| ------ | ------ | ----- | ----------- |
| First Contentful Paint | 1.8s | 0.9s | 50% |
| Time to Interactive | 5.2s | 2.8s | 46% |

cc: @octocat @monalisa`,
    viewerCanUpdate: false,
    onSave: (newBody, onCompleted, _) => {
      setTimeout(() => {
        onCompleted()
      }, 1000)
    },
  },
}
