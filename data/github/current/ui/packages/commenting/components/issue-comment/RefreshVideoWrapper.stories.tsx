import type {SafeHTMLString} from '@github-ui/safe-html'
import type {Meta, StoryObj} from '@storybook/react'
import {useRef} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'
import {graphql} from 'relay-runtime'
import {createMockEnvironment} from 'relay-test-utils'

import {RefreshVideoWrapper} from './RefreshVideoWrapper'

// Mock query for story purposes
const mockQuery = graphql`
  query RefreshVideoWrapperStoryQuery @relay_test_operation {
    node(id: "test-id") {
      ... on Node {
        id
      }
    }
  }
`

// Create a wrapper component with all necessary providers and state
const RefreshVideoWrapperWithProviders = (props: React.ComponentProps<typeof RefreshVideoWrapper>) => {
  const environment = createMockEnvironment()
  const bodyRef = useRef<HTMLDivElement>(null)
  const {id = 'test-id', getHTML, bodyHTML, children, ...rest} = props

  return (
    <RelayEnvironmentProvider environment={environment}>
      <RefreshVideoWrapper id={id} bodyHTML={bodyHTML} getHTML={getHTML} {...rest}>
        <div className="markdown-body" data-testid="markdown-body" ref={bodyRef}>
          {children || (
            <>
              <p>This content contains media that will be refreshed on hover after a timeout period.</p>
              <video
                src="original-src"
                controls
                width="400"
                height="300"
                preload="metadata"
                aria-label="Sample video content"
                muted
              />
            </>
          )}
        </div>
      </RefreshVideoWrapper>
    </RelayEnvironmentProvider>
  )
}

const meta = {
  title: 'Commenting/RefreshVideoWrapper',
  component: RefreshVideoWrapperWithProviders,
  parameters: {
    controls: {expanded: true},
    layout: 'padded',
  },
  tags: ['autodocs'],
  argTypes: {
    id: {
      control: 'text',
      description: 'ID of the content to be refreshed',
    },
    bodyHTML: {
      control: 'text',
      description: 'HTML content containing video/image elements to refresh',
    },
    children: {
      control: false,
      description: 'Children elements to be wrapped',
    },
  },
  decorators: [
    Story => (
      <div className="color-bg-default p-3" style={{maxWidth: '700px'}}>
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof RefreshVideoWrapperWithProviders>

export default meta
type Story = StoryObj<typeof meta>

// Default story with video content
export const WithVideoContent: Story = {
  args: {
    id: 'test-id',
    query: mockQuery,
    bodyRef: {current: null},
    // eslint-disable-next-line github/unescaped-html-literal
    bodyHTML: '<video />' as SafeHTMLString,
    getHTML: () => '',
    children: undefined,
  },
  parameters: {
    docs: {
      description: {
        story: 'Shows a RefreshVideoWrapper with video content that refreshes (and clears) on hover after a timeout.',
      },
    },
  },
}
