import type {Meta} from '@storybook/react'
import {CopilotSummarizeBannerLoader, type CopilotSummarizeBannerLoaderProps} from './CopilotSummarizeBannerLoader'
import {HttpResponse, http} from 'msw'

const mockedBannerPath = '/monalisa/smile/issues/1/copilot-summaries-banner'

const meta = {
  title: 'Recipes/CopilotSummarizeBannerLoader',
  component: CopilotSummarizeBannerLoader,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [http.get(mockedBannerPath, () => HttpResponse.html('Mock Banner Content'))],
    },
  },
  argTypes: {
    bannerPath: {control: 'text', defaultValue: mockedBannerPath},
  },
} satisfies Meta<typeof CopilotSummarizeBannerLoader>

export default meta

const defaultArgs: Partial<CopilotSummarizeBannerLoaderProps> = {
  bannerPath: mockedBannerPath,
}

export const CopilotSummarizeBannerLoaderExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: CopilotSummarizeBannerLoaderProps) => <CopilotSummarizeBannerLoader {...args} />,
}
