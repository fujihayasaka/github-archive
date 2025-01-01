import type {Meta} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {RepositoryPropertyTarget, type RepositoryPropertyTargetProps} from './RepositoryPropertyTarget'
import type {PropertyConfiguration, RepositoryPropertyParameters} from '../../../types/rules-types'
import {useState} from 'react'

const meta: Meta = {
  title: 'Apps/Rulesets/Ruleset Page/RepositoryPropertyTarget',
  decorators: [storyWrapper()],
}

export default meta

const defaultIncludeParameters: PropertyConfiguration[] = [
  {name: 'database', source: 'custom', property_values: ['mysql']},
  {name: 'fork', source: 'system', property_values: ['true']},
  {name: 'language', source: 'system', property_values: ['python']},
]

const defaultProps: RepositoryPropertyTargetProps = {
  parameters: {
    include: defaultIncludeParameters,
    exclude: [],
  },
  readOnly: false,
  rulesetTarget: 'branch',
  updateParameters: () => undefined,
  blankslate: {
    heading: 'No repository targets have been added yet',
  },
}

export const Default = () => {
  return <RepositoryPropertyTarget {...defaultProps} />
}

export const DynamicPicker = () => {
  const [parameters, setParameters] = useState(defaultProps.parameters)

  return (
    <RepositoryPropertyTarget
      {...defaultProps}
      parameters={parameters}
      updateParameters={params => setParameters(params as RepositoryPropertyParameters)}
    />
  )
}

DynamicPicker.parameters = {
  storyWrapper: {appPayload: {['enabled_features']: {['repos_picker_in_ruleset']: true}}},
}
