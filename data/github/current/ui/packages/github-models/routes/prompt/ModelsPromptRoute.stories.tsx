import {HttpResponse, delay, http} from 'msw'
import type {Meta, StoryObj} from '@storybook/react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Model} from '@github-ui/marketplace-common'
import {modelEvalsPath, modelPlaygroundPath, modelPromptPath} from '@github-ui/paths'
import type {GettingStartedPayload} from '../../types'
import {ModelsPromptRoute} from './ModelsPromptRoute'
import type {AppPayloadWithFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {mockGettingStarted, mockModel, mockModelInputSchema} from '../playground/__tests__/mocks'
import {parametersConfig} from '../../utils/story-utils'

const meta: Meta<GettingStartedPayload> = {
  title: 'Apps/GitHub Models/ModelsPromptRoute',
  component: ModelsPromptRoute,
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
    playgroundUrl: modelPlaygroundPath(mockModel),
    modelEvaluation: mockModel.evaluation as SafeHTMLString,
    canProvideAdditionalFeedback: false,
    isLoggedIn: true,
    restrictedModels: [],
  },
  parameters: {
    ...parametersConfig,
    msw: {
      handlers: [
        http.get('/marketplace/models', async () => {
          await delay(1000)
          const model2 = Object.assign({}, mockModel, {
            id: `${mockModel.id}-2`,
            name: 'model-2',
            friendly_name: 'Model 2',
          })
          const model3 = Object.assign({}, mockModel, {
            id: `${mockModel.id}-3`,
            name: 'model-3',
            friendly_name: 'Really Quite A Very Long Model Name You Would Not Believe',
          })
          const model4 = Object.assign({}, mockModel, {
            id: `${mockModel.id}-4`,
            name: 'model-4-o1-mini',
            friendly_name: 'An O1 Mini Model',
          })
          return HttpResponse.json([mockModel, model2, model3, model4] as Model[])
        }),
      ],
    },
  },
  argTypes: {
    restrictedModels: {control: {type: 'object'}},
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

function appPayloadWithEnabledFeature(featureFlag: string): AppPayloadWithFeatureFlags {
  return {enabled_features: {[featureFlag]: true}}
}

export const Prompt: StoryObj = {
  render: () => <ModelsPromptRoute />,
  decorators: [
    (Story, {args: routePayload}) => (
      <Wrapper
        appPayload={appPayloadWithEnabledFeature('github_models_prompt_editor')}
        pathname={modelPromptPath(mockModel)}
        routePayload={routePayload}
      >
        <Story />
      </Wrapper>
    ),
  ],
}

export const Evals: StoryObj = {
  render: () => <ModelsPromptRoute />,
  decorators: [
    (Story, {args: routePayload}) => (
      <Wrapper
        appPayload={appPayloadWithEnabledFeature('github_models_prompt_evals')}
        pathname={modelEvalsPath(mockModel)}
        routePayload={routePayload}
      >
        <Story />
      </Wrapper>
    ),
  ],
}
