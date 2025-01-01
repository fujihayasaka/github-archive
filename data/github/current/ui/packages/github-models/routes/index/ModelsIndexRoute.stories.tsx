import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {IndexModelsPayload} from '../../types'
import {mockModel} from '../playground/__tests__/mocks'
import {mockCategory} from '@github-ui/marketplace-common/mock-data'
import {ModelsIndexRoute} from './ModelsIndexRoute'
import {parametersConfig} from '../../utils/story-utils'

const meta: Meta<IndexModelsPayload> = {
  title: 'Apps/GitHub Models/ModelsIndexRoute',
  component: ModelsIndexRoute,
  args: {
    models: [
      mockModel,
      Object.assign({}, mockModel, {id: 'foo', name: 'foo-model', friendly_name: 'The Great Foo'}),
      Object.assign({}, mockModel, {id: 'bar', name: 'bar-model', friendly_name: 'Bar v2'}),
      Object.assign({}, mockModel, {id: 'baz', name: 'baz-model', friendly_name: 'Inexorable Baz'}),
    ],
    categories: {apps: [mockCategory()], actions: [mockCategory()]},
  },
  argTypes: {
    models: {control: 'object'},
    categories: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

export const Example: StoryObj = {
  render: () => <ModelsIndexRoute />,
  decorators: [
    (Story, {args: routePayload}) => (
      <Wrapper pathname="/marketplace/models" routePayload={routePayload}>
        <Story />
      </Wrapper>
    ),
  ],
}
