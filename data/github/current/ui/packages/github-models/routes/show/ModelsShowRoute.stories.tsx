import type {Meta, StoryObj} from '@storybook/react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {ModelsShowRoute} from './ModelsShowRoute'
import type {GettingStartedPayload} from '../../types'
import {ModelUrlHelper} from '../../utils/model-url-helper'
import {mockGettingStarted, mockModel, mockModelInputSchema} from '../playground/__tests__/mocks'

const meta = {
  title: 'Apps/GitHub Models/ModelsShowRoute',
  component: ModelsShowRoute,
} satisfies Meta<typeof ModelsShowRoute>

export default meta

type Story = StoryObj<typeof ModelsShowRoute>

const routePayload: GettingStartedPayload = {
  gettingStarted: mockGettingStarted,
  model: mockModel,
  modelInputSchema: mockModelInputSchema,
  modelReadme:
    // eslint-disable-next-line github/unescaped-html-literal
    '<h2>Readme</h2><p>Lorem ipsum odor amet, consectetuer adipiscing elit. Mattis imperdiet nisl ad posuere ornare, per donec mollis. Vestibulum pulvinar ullamcorper cubilia velit tempus morbi volutpat vehicula. Facilisis aenean interdum class feugiat vestibulum enim rutrum quam. Apellentesque mauris curabitur egestas suscipit.</p><h3>Secondary section</h3><p>Torquent justo nam mus commodo vehicula ultricies phasellus phasellus. Vulputate malesuada turpis ante facilisis vehicula, fringilla torquent est. Ullamcorper pulvinar bibendum placerat maecenas mus convallis id habitant. Ligula in augue ultrices purus magna leo.</p><p><a href="#">Erat fames</a> eros sagittis luctus habitant congue inceptos senectus. Curabitur urna inceptos enim taciti eleifend. Vehicula proin vivamus finibus posuere dapibus imperdiet massa phasellus ultricies. Per ridiculus non tristique ligula pharetra luctus est. Mus dapibus lacus quisque ridiculus inceptos torquent.</p>' as SafeHTMLString,
  modelLicense: mockModel.license as SafeHTMLString,
  readmeToc: [],
  modelTransparencyContent:
    // eslint-disable-next-line github/unescaped-html-literal
    '<h2>A note about transparency</h2><p>Suspendisse sit amet dui facilisis nunc mattis iaculis. Vivamus quis tempor dui, ac efficitur risus. Ut dignissim turpis in ex tincidunt viverra. Integer iaculis lacus a sapien gravida, vitae blandit justo fringilla. Nam tristique dolor nibh, <a href="#">ac sagittis</a> urna lobortis nec.</p><p>Duis interdum convallis massa at porta. Fusce ligula lectus, facilisis eu est sed, facilisis mattis dui. Nulla sit amet tortor convallis, lobortis elit non, semper tortor. Vestibulum vel odio ligula. Fusce tempus ante at nulla luctus, eu vestibulum arcu viverra. Nulla interdum tortor vel ex pellentesque, a venenatis odio tempor. Maecenas mollis, lacus in laoreet tempus, justo sapien laoreet neque, non laoreet metus tortor et magna. Maecenas eget iaculis sapien. Nam commodo tellus at neque dignissim semper.</p>' as SafeHTMLString,
  playgroundUrl: ModelUrlHelper.playgroundUrl(mockModel),
  modelEvaluation: mockModel.evaluation as SafeHTMLString,
  canProvideAdditionalFeedback: false,
  isLoggedIn: true,
  canUseO1Models: true,
}

const modelUrl = ModelUrlHelper.modelUrl(mockModel)

export const Readme: Story = {
  render: () => <ModelsShowRoute />,
  decorators: [storyWrapper({routePayload, pathname: modelUrl})],
}

export const Evaluation: Story = {
  render: () => <ModelsShowRoute />,
  decorators: [storyWrapper({routePayload, pathname: modelUrl, search: '?tab=evaluation'})],
}

export const License: Story = {
  render: () => <ModelsShowRoute />,
  decorators: [storyWrapper({routePayload, pathname: modelUrl, search: '?tab=license'})],
}

export const Transparency: Story = {
  render: () => <ModelsShowRoute />,
  decorators: [storyWrapper({routePayload, pathname: modelUrl, search: '?tab=transparency'})],
}
