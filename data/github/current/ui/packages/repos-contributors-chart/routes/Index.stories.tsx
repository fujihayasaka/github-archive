import type {Meta} from '@storybook/react'
import {HttpResponse, http} from 'msw'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {Index, type IndexProps} from './Index'
import smallData from '../test-utils/small-data'
import bigData from '../test-utils/big-data'

import {RangeSelectionProvider} from '../contexts/RangeSelectionContext'
import {CalculatedMaxProvider} from '../contexts/CalculatedMaxContext'

interface StoryProps extends IndexProps {
  repos_column_charts: boolean
}

const meta = {
  title: 'Apps/Repo Contributors/Index',
  component: Index,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        http.get(`/contributors-small-data`, () => {
          return HttpResponse.json(smallData)
        }),

        http.get(`/contributors-big-data`, () => {
          return HttpResponse.json(bigData)
        }),
      ],
    },
    // TODO This should be fixed upstream in the chart-card package
    a11y: {
      element: '#storybook-root',
      config: {
        rules: [
          {
            id: 'landmark-unique',
            enabled: false,
          },
        ],
      },
    },
  },
  args: {
    repos_column_charts: true,
  },
  argTypes: {
    repos_column_charts: {control: {type: 'boolean'}},
  },
} satisfies Meta<StoryProps>

export default meta

const defaultArgs: Partial<IndexProps> = {
  graphDataPath: '/contributors-small-data',
  isUsingContributionInsights: true,
  defaultBranch: 'main',
}

const bigDataArgs: Partial<IndexProps> = {
  graphDataPath: '/contributors-big-data',
  isUsingContributionInsights: true,
  defaultBranch: 'main',
}

export const SmallChart = {
  args: defaultArgs,
  render: (args: StoryProps) => <WrappedChart {...args} />,
}

export const BigChart = {
  args: bigDataArgs,
  render: (args: StoryProps) => <WrappedChart {...args} />,
}

const WrappedChart = ({repos_column_charts, ...args}: Partial<StoryProps>) => (
  <Wrapper appPayload={{enabled_features: {repos_column_charts}}} routePayload={args}>
    <CalculatedMaxProvider>
      <RangeSelectionProvider>
        <Index />
      </RangeSelectionProvider>
    </CalculatedMaxProvider>
  </Wrapper>
)
