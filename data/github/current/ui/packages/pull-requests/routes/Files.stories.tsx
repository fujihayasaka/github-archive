import type {Meta, StoryObj} from '@storybook/react'
import {Files} from './Files'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {getFilesRoutePayload} from '../test-utils/files-mock-data'

const meta: Meta<typeof Files> = {
  title: 'Pull Requests/Files',
  component: Files,
  decorators: [
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={`${BASE_PAGE_DATA_URL}/files`}>
          <Story />
        </PageDataContextProvider>
      )
    },
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
}

export default meta

const defaultRoutePayload = getFilesRoutePayload()
const defaultAppPayload = {helpUrl: ''}

type Story = StoryObj<typeof Files>

export const NoDiffsNoTree: Story = {
  render: () => (
    <Wrapper routePayload={defaultRoutePayload} appPayload={defaultAppPayload}>
      <Files />
    </Wrapper>
  ),
}
