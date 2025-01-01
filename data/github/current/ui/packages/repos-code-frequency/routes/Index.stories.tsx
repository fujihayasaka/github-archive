import {Route, Routes} from 'react-router-dom'
import type {Meta} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {HttpResponse, http} from 'msw'
import {Index, type IndexPayload} from './Index'
import {getAggregateData, getIndexRoutePayload} from '../test-utils/mock-data'

interface StoryProps extends IndexPayload {
  repos_column_charts: boolean
}

const meta = {
  title: 'Apps/Repo Code Frequency/Index',
  component: Index,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        http.get(getIndexRoutePayload().graphDataPath, () => {
          return HttpResponse.json(getAggregateData())
        }),
      ],
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

const defaultArgs: StoryProps = {
  ...getIndexRoutePayload(),
  repos_column_charts: true,
}
const route = jsonRoute({
  path: '/:owner/:repo/graphs/code-frequency',
  Component: Index,
})

export const ReposCodeFrequencyChartExample = {
  args: defaultArgs,
  render: ({repos_column_charts, ...args}: StoryProps) => (
    <Wrapper
      appPayload={{enabled_features: {repos_column_charts}}}
      routePayload={args}
      pathname="/repos-security/insights/graphs/code-frequency"
      routes={[route]}
    >
      <Routes>
        <Route path={route.path} element={<Index />} />
      </Routes>
    </Wrapper>
  ),
}
