import type {PropertyDefinition} from '@github-ui/custom-properties-types'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import type {ComponentProps} from 'react'
import {Route, Routes} from 'react-router-dom'

import {CurrentOrgRepoProvider} from '../contexts/CurrentOrgRepoContext'
import {businessCustomPropertiesRoute, definitionsRoute} from '../custom-properties'
import {sampleBusinessSource, sampleStorybookDefinitions} from '../test-utils/mock-data'
import {DefinitionsList} from './DefinitionsList'

type StoryArgs = {
  settingsLevel: 'organizations' | 'enterprises'
}

const meta: Meta<StoryArgs> = {
  title: 'Apps/Custom Properties/Components/DefinitionsList',
  decorators: [
    (Story, {args}) => {
      const pathname = `/${args.settingsLevel}/github/settings/custom-properties`
      const isOrgPath = args.settingsLevel === 'organizations'
      const route = isOrgPath ? definitionsRoute : businessCustomPropertiesRoute

      return (
        <Wrapper pathname={pathname} routes={[route]}>
          <Routes>
            <Route
              path={route.path}
              element={
                <CurrentOrgRepoProvider>
                  <Story />
                </CurrentOrgRepoProvider>
              }
            />
          </Routes>
        </Wrapper>
      )
    },
  ],
  args: {
    settingsLevel: 'organizations',
  },
  argTypes: {
    settingsLevel: {
      options: ['organizations', 'enterprises'],
      control: {type: 'radio'},
    },
  },
}

export default meta

const bizProps: PropertyDefinition[] = [
  {
    propertyName: 'global_id',
    valueType: 'string',
    valuesEditableBy: 'org_and_repo_actors',
    description: 'Repo id in the internal business index',
    required: false,
    defaultValue: null,
    allowedValues: null,
    regex: null,
    source: sampleBusinessSource,
  },
]

const definitions: PropertyDefinition[] = [...sampleStorybookDefinitions, ...bizProps]

const sampleProps: ComponentProps<typeof DefinitionsList> = {
  definitions,
  totalCount: 113,
}

export const Default = () => <DefinitionsList {...sampleProps} />

export const NoResults = () => <DefinitionsList {...sampleProps} definitions={[]} />
