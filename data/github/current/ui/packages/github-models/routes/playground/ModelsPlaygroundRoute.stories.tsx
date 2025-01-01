import type {Meta, StoryObj} from '@storybook/react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {GettingStartedPayload} from '../../types'
import {ModelsPlaygroundRoute} from './ModelsPlaygroundRoute'
import {ModelUrlHelper} from '../../utils/model-url-helper'
import {mockGettingStarted, mockModel, mockModelInputSchema} from '../playground/__tests__/mocks'
import {parametersConfig} from '../../utils/story-utils'

const meta: Meta<GettingStartedPayload> = {
  title: 'Apps/GitHub Models/ModelsPlaygroundRoute',
  component: ModelsPlaygroundRoute,
  args: {
    gettingStarted: mockGettingStarted,
    model: mockModel,
    modelInputSchema: mockModelInputSchema,
    modelReadme:
      // eslint-disable-next-line github/unescaped-html-literal
      '<h2>Readme</h2><p>How doth the little crocodile<br>Improve his shining tail<br>And pour the waters of the Nile<br>On every golden scale!</p> <p>How cheerfully he seems to grin,<br>How neatly spreads his claws,<br>And welcomes little fishes in<br>With gently smiling jaws!</p>' as SafeHTMLString,
    modelLicense: mockModel.license as SafeHTMLString,
    readmeToc: [],
    modelTransparencyContent:
      // eslint-disable-next-line github/unescaped-html-literal
      '<h2>Content Filtering</h2><p>’Twas brillig, and the slithy toves<br>Did gyre and gimble in the wabe:<br>All mimsy were the borogoves,<br>And the mome raths outgrabe.</p><p>“Beware the Jabberwock, my son!<br>The jaws that bite, the claws that catch!<br>Beware the Jubjub bird, and shun<br>The frumious Bandersnatch!”</p>' as SafeHTMLString,
    playgroundUrl: ModelUrlHelper.playgroundUrl(mockModel),
    modelEvaluation: mockModel.evaluation as SafeHTMLString,
    canProvideAdditionalFeedback: false,
    isLoggedIn: true,
    canUseO1Models: true,
  },
  parameters: parametersConfig,
  argTypes: {
    canUseO1Models: {control: {type: 'boolean'}},
    isLoggedIn: {control: {type: 'boolean'}},
    canProvideAdditionalFeedback: {control: {type: 'boolean'}},
    modelReadme: {control: {type: 'text'}},
    modelEvaluation: {control: {type: 'text'}},
    modelTransparencyContent: {control: {type: 'text'}},
    modelLicense: {control: {type: 'text'}},
    playgroundUrl: {control: {type: 'text'}},
    gettingStarted: {control: 'object'},
    model: {control: 'object'},
    readmeToc: {control: 'object'},
    modelInputSchema: {control: 'object'},
  },
}

export default meta

export const Example: StoryObj = {
  render: () => <ModelsPlaygroundRoute />,
  decorators: [
    (Story, {args: routePayload}) => (
      <Wrapper pathname={ModelUrlHelper.playgroundUrl(mockModel)} routePayload={routePayload}>
        <Story />
      </Wrapper>
    ),
  ],
}
