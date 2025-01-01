import type {Meta, StoryObj} from '@storybook/react'

import {TargetsPanel} from '../TargetsPanel'

import {conditions} from '../../../state/__tests__/helpers'
import type {Condition} from '../../../types/rules-types'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {http, HttpResponse} from 'msw'
import type {PropertyDefinition} from '@github-ui/repos-filter'

export const sampleDefinitions: PropertyDefinition[] = [
  {
    propertyName: 'multiSelect',
    valueType: 'multi_select',
    allowedValues: ['production', 'staging', 'development'],
  },
  {
    propertyName: 'singleSelect',
    valueType: 'single_select',
    allowedValues: ['mysql', 'postgres', 'mongodb'],
  },
]

const meta: Meta<typeof TargetsPanel> = {
  title: 'Apps/Rulesets/Ruleset Page/TargetsPanel',
  component: TargetsPanel,
  decorators: [
    (Story, {args}) => {
      return (
        <Wrapper
          appPayload={{
            enabled_features: {
              repos_picker_in_ruleset: true,
              repos_rulesets_default_to_repository_property: true,
              ruleset_allow_dup_multi_select_props: true,
            },
          }}
        >
          <Story {...args} />
        </Wrapper>
      )
    },
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        http.get(`/repositories/picker/definitions`, () => {
          return HttpResponse.json({definitions: sampleDefinitions})
        }),
      ],
    },
  },
  tags: ['flaky'],
  args: {
    readOnly: false,
    rulesetId: 1,
    rulesetTarget: 'branch',
    rulesetPreviewCount: 1,
    rulesetPreviewSamples: ['smile'],
    fnmatchHelpUrl: 'https://github.com',
    supportedConditionTargetObjects: ['ref', 'repository'],
    conditions,
    dirtyConditions: [],
    source: createRepository({name: 'acme'}),
    sourceType: 'organization',
  },
  argTypes: {
    readOnly: {
      control: 'boolean',
      defaultValue: false,
    },
    rulesetTarget: {
      options: ['branch', 'tag'],
      control: {
        type: 'radio',
      },
      defaultValue: 'branch',
    },
    fnmatchHelpUrl: {
      control: 'text',
      defaultValue: 'https://github.com',
    },
    addOrUpdateCondition: {
      action: 'Add or update condition',
    },
    removeCondition: {
      action: 'Remove condition',
    },
    sourceType: {
      options: ['repository', 'organization'],
      control: {
        type: 'radio',
      },
      defaultValue: 'organization',
    },
  },
}

export default meta
type Story = StoryObj<typeof TargetsPanel>

export const PopulatedOrg: Story = {}

export const PopulatedEnterprise: Story = {
  args: {
    sourceType: 'enterprise',
  },
}

export const PopulatedRepo: Story = {
  args: {
    sourceType: 'repository',
    rulesetPreviewSamples: ['main'],
    conditions: conditions.filter(c => c.target === 'ref_name'),
    supportedConditionTargetObjects: ['ref'],
  },
}

export const MoreThan10Repos: Story = {
  args: {
    rulesetPreviewCount: 30,
    rulesetPreviewSamples: new Array(10).fill(0).map((_, index) => `smile-${index}`),
  },
}

export const MultipleRepos: Story = {
  args: {
    rulesetPreviewCount: 5,
    rulesetPreviewSamples: new Array(5).fill(0).map((_, index) => `smile-${index}`),
  },
}

const propertyConditions: Condition[] = [
  {
    target: 'repository_property',
    parameters: {
      exclude: [],
      include: [
        {
          name: 'database',
          source: 'custom',
          property_values: ['mysql'],
        },
      ],
    },
    _dirty: false,
  },
]

export const PropertyRuleset: Story = {
  args: {
    conditions: propertyConditions,
    rulesetPreviewCount: 5,
    rulesetPreviewSamples: [],
  },
}

export const Empty: Story = {
  args: {
    conditions: [],
    rulesetPreviewCount: undefined,
    rulesetPreviewSamples: undefined,
  },
}

export const NoTargets: Story = {
  args: {
    conditions: [],
    rulesetPreviewCount: 0,
    rulesetPreviewSamples: [],
  },
}

export const ShowErrorHighNumberTargets: Story = {
  args: {
    rulesetError: 'Unable to display affected targets due to a large number of branches in this repository.',
  },
}
