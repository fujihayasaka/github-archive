import type {Meta} from '@storybook/react'
import {RequiredReviewers, type PullRequestRuleMetadata, type RequiredReviewer} from '../RequiredReviewers'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {
  mockRequiredReviewers as reviewers,
  mockRequiredReviewersWithMissingTeam as reviewersWithMissingTeam,
  mockRequiredReviewerMetadata as reviewerMetadata,
  mockRequiredReviewerMetadataWithMissingTeam as reviewerMetadataWithMissingTeam,
  mockRequiredReviewerSuggestions as suggestions,
  requiredReviewerField,
} from '../__tests__/helpers'
import {useState} from 'react'
import type {ParameterValue, RegisteredRuleSchemaComponent, SchemaField} from '../../../types/rules-types'

type RequiredReviewersType = typeof RequiredReviewers

// This override is required to mock the suggestions request.
global.fetch = async url => {
  if (url.toString().includes('suggestions')) {
    return new Response(JSON.stringify(suggestions))
  } else {
    return {ok: false, status: 404, json: async () => ({})} as Response
  }
}

const meta: Meta<RequiredReviewersType> = {
  title: 'Apps/Rulesets/Rule Schema/RequiredReviewers',
  component: RequiredReviewers,
  decorators: [
    (Story, {args}) => {
      return (
        <Wrapper>
          <Story {...args} />
        </Wrapper>
      )
    },
  ],
  parameters: {
    controls: {
      expanded: true,
      sort: 'alpha',
      // We only want to include controls for params that
      // will change the UI in a meaningful way
      include: ['readOnly', 'value', 'errors', 'metadata'],
    },
  },
  argTypes: {
    readOnly: {
      control: 'boolean',
      defaultValue: false,
    },
  },
}

export default meta

const defaultArgs = {
  readOnly: false,
  rulesetId: 1,
  sourceType: 'repository',
  field: requiredReviewerField as SchemaField,
  value: reviewers,
  errors: [],
  metadata: reviewerMetadata,
}

export const WithReviewers = (props: RegisteredRuleSchemaComponent) => {
  const [value, setValue] = useState<ParameterValue>(reviewers)

  const handleValueChange = (newValue: ParameterValue) => {
    setValue(newValue)
  }

  return <RequiredReviewers {...defaultArgs} {...props} value={value} onValueChange={handleValueChange} />
}

export const MissingReviewer = (props: RegisteredRuleSchemaComponent) => {
  const [value, setValue] = useState<ParameterValue>(reviewersWithMissingTeam)

  const handleValueChange = (newValue: ParameterValue) => {
    setValue(newValue)
  }

  return (
    <RequiredReviewers
      {...defaultArgs}
      {...props}
      metadata={reviewerMetadataWithMissingTeam}
      value={value}
      onValueChange={handleValueChange}
    />
  )
}

export const NoReviewers = (props: RegisteredRuleSchemaComponent) => {
  const [value, setValue] = useState<ParameterValue>([])

  const handleValueChange = (newValue: ParameterValue) => {
    setValue(newValue)
  }

  return <RequiredReviewers {...defaultArgs} {...props} metadata={{}} value={value} onValueChange={handleValueChange} />
}

export const Pagination = (props: RegisteredRuleSchemaComponent) => {
  const paginationReviewers = [] as RequiredReviewer[]
  const paginationMetadata = {requiredReviewers: {}} as PullRequestRuleMetadata
  // Iterate over a range of 12 to add reviewers
  for (let i = 0; i < 12; i++) {
    paginationReviewers.push({
      reviewer_id: `T_${i}`,
      minimum_approvals: i,
      file_patterns: ['**/*.md'],
    })
    paginationMetadata.requiredReviewers[`T_${i}`] = {
      id: i,
      globalRelayId: `T_${i}`,
      type: 'Team',
      name: `Team ${i}`,
    }
  }
  const [value, setValue] = useState<ParameterValue>(paginationReviewers)

  const handleValueChange = (newValue: ParameterValue) => {
    setValue(newValue)
  }

  return (
    <RequiredReviewers
      {...defaultArgs}
      {...props}
      metadata={paginationMetadata}
      value={value}
      onValueChange={handleValueChange}
    />
  )
}

export const TruncatedFilePath = (props: RegisteredRuleSchemaComponent) => {
  const truncatedReviewer = [
    {
      reviewer_id: 'T_1',
      minimum_approvals: 1,
      file_patterns: ['**/a/very/long/path/that/should/be/truncated/for/testing/purposes.md'],
    },
  ]

  const truncatedMetadata = {
    requiredReviewers: {
      T_1: {
        id: 1,
        globalRelayId: 'T_1',
        type: 'Team',
        name: 'Important Team',
      },
    },
  }

  const [value, setValue] = useState<ParameterValue>(truncatedReviewer)

  const handleValueChange = (newValue: ParameterValue) => {
    setValue(newValue)
  }

  return (
    <RequiredReviewers
      {...defaultArgs}
      {...props}
      value={value}
      metadata={truncatedMetadata}
      onValueChange={handleValueChange}
    />
  )
}

export const MultipleFilePatterns = (props: RegisteredRuleSchemaComponent) => {
  const reviewersWithManyPatterns = [
    {
      reviewer_id: 'T_1',
      minimum_approvals: 1,
      file_patterns: ['**/*.js', '**/*.ts', '**/*.tsx', '**/*.go'],
    },
    {
      reviewer_id: 'T_2',
      minimum_approvals: 1,
      file_patterns: [
        'sql/**',
        'db/**',
        '**/a/very/long/path/that/should/be/truncated/for/testing/purposes.md',
        'data/**',
        '**/*.sql',
        '**/another/very/long/path/that/should/be/truncated/for/testing/purposes.md',
        '**/*.db',
        '**/another/very/long/path/that/should/be/truncated/for/testing/purposes.md',
        '**/*.data',
      ],
    },
    {
      reviewer_id: 'T_3',
      minimum_approvals: 1,
      file_patterns: ['*'],
    },
  ]

  const manyPatternsMetadata = {
    requiredReviewers: {
      T_1: {
        id: 1,
        globalRelayId: 'T_1',
        type: 'Team',
        name: 'Web Dev',
      },
      T_2: {
        id: 2,
        globalRelayId: 'T_2',
        type: 'Team',
        name: 'Databases',
      },
      T_3: {
        id: 3,
        globalRelayId: 'T_3',
        type: 'Team',
        name: 'Security',
      },
    },
  }

  const [value, setValue] = useState<ParameterValue>(reviewersWithManyPatterns)

  const handleValueChange = (newValue: ParameterValue) => {
    setValue(newValue)
  }

  return (
    <RequiredReviewers
      {...defaultArgs}
      {...props}
      value={value}
      metadata={manyPatternsMetadata}
      onValueChange={handleValueChange}
    />
  )
}
