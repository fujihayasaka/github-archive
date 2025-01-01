import {FormControl} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {useState} from 'react'

import {mockSelectorModel} from '../test-utils/mocks'
import type {SelectorCustomModel} from '../types'
import {ModelSelectorPane} from './ModelSelectorPane'

function generateBulkModels() {
  const models: SelectorCustomModel[] = []
  const selected: Array<SelectorCustomModel['slug']> = []
  for (let i = 0; i < 50; i++) {
    const m = mockSelectorModel({
      slug: `model-${i + 1}`,
      fresh: i % 4 === 0,
      deprecated: i % 3 === 0,
      name: i % 5 === 0 ? `Model ${i + 1}` : undefined,
    })
    models.push(m)
    if (i % 2 === 0) {
      selected.push(m.slug)
    }
  }
  return {models, selected}
}

export default {
  title: 'Apps/Models BYOK settings/Components/ModelSelectorPane',
  component: ModelSelectorPane,
  args: {
    models: [],
    selected: [],
    editable: true,
    onSelect: fn(),
    onLabelUpdate: fn(),
  },
  decorators: [
    Story => (
      <div style={{maxWidth: 437}}>
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof ModelSelectorPane>

type Story = StoryObj<typeof ModelSelectorPane>

export const Default: Story = {}

export const Playground: Story = {
  args: generateBulkModels(),
  render(args) {
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const [selectedModels, setSelected] = useState(args.selected)
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const [models, setModels] = useState(args.models)

    return (
      <ModelSelectorPane
        {...args}
        models={models}
        onLabelUpdate={(newValue, model) => {
          setModels(prev => {
            return prev.map(item => {
              if (item.slug === model.slug) {
                return {...item, name: newValue.length ? newValue : undefined}
              }
              return item
            })
          })
        }}
        onSelect={(_selected, model) => {
          setSelected(prev => {
            const newSelected = [...prev]
            const maybeSelected = newSelected.indexOf(model.slug)
            if (~maybeSelected) {
              newSelected.splice(maybeSelected, 1)
            } else {
              newSelected.push(model.slug)
            }
            return newSelected
          })
        }}
        selected={selectedModels}
      />
    )
  },
}

export const WithLoading: Story = {
  args: {
    loading: true,
    models: [],
    selected: [],
  },
}

export const InAFormContol: Story = {
  args: generateBulkModels(),
  decorators: [
    Story => (
      <div style={{maxHeight: '80vh', display: 'flex', flexDirection: 'column'}}>
        <FormControl>
          <FormControl.Label>Models</FormControl.Label>
          <Story />
        </FormControl>
      </div>
    ),
  ],
}

export const StretchTest: Story = {
  args: generateBulkModels(),
  decorators: [
    Story => (
      <div
        style={{
          height: '80dvh',
          border: '1px solid var(--borderColor-danger-emphasis)',
          padding: 'var(--base-size-4)',
          gap: 'var(--stack-gap-condensed)',
          display: 'flex',
          flexDirection: 'column',
        }}
        data-testid="model-selector-pane-container"
      >
        <Banner title="story top" hideTitle aria-label="Story top" data-testid="story-top-banner">
          This story tests that the ModelSelectorPane, when in a flex grow container, can stretch to fill the available
          height.
          <br /> This Banner should be at the top.
        </Banner>
        <Story />
        <Banner title="story bottom" aria-label="Story bottom" data-testid="story-bottom-banner">
          and this Banner should be at the bottom. Within a bounded container height.
        </Banner>
      </div>
    ),
  ],
}
