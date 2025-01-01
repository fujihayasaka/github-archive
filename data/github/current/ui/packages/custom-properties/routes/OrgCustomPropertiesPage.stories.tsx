import type {OrgCustomPropertiesSetValuesPagePayload} from '@github-ui/custom-properties-types'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {Route, Routes} from 'react-router-dom'

import {BannerProvider} from '../contexts/BannerContext'
import {definitionsRoute} from '../custom-properties'
import {sampleBusinessSource, sampleOrgSource, sampleRepos} from '../test-utils/mock-data'
import {OrgCustomPropertiesPage} from './OrgCustomPropertiesPage'

const routePayload: OrgCustomPropertiesSetValuesPagePayload = {
  ownDefinitionsCount: 5,
  activeTab: 'set-values',
  definitions: [
    {
      propertyName: 'album',
      valueType: 'string',
      required: false,
      defaultValue: null,
      description: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
      allowedValues: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleOrgSource,
    },
    {
      propertyName: 'band',
      valueType: 'single_select',
      required: true,
      defaultValue: 'Rammstein',
      description:
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut suscipit ex ante, eget ornare sem congue id. Sed tortor elit, bibendum non nibh at, consequat convallis nisi',
      allowedValues: ['Rammstein', 'Metallica'],
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleOrgSource,
    },
    {
      propertyName: 'singer',
      valueType: 'string',
      required: false,
      defaultValue: null,
      description: null,
      allowedValues: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleOrgSource,
    },
    {
      propertyName: 'long_property_name',
      valueType: 'string',
      required: false,
      defaultValue: null,
      description:
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed tortor elit, bibendum non nibh at, consequat convallis nisi. Ut suscipit ex ante, eget ornare sem congue id.',
      allowedValues: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleOrgSource,
    },
    {
      propertyName: 'required_long_property_name',
      valueType: 'string',
      required: true,
      defaultValue: 'default',
      description:
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut suscipit ex ante, eget ornare sem congue id. Sed tortor elit, bibendum non nibh at, consequat convallis nisi',
      allowedValues: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleBusinessSource,
    },
  ],
  repositories: sampleRepos,
  repositoryCount: sampleRepos.length,
  pageCount: 1,
  permissions: 'all',
}

const meta: Meta = {
  title: 'Apps/Custom Properties/OrgCustomPropertiesPage',
  component: OrgCustomPropertiesPage,
  decorators: [
    (Story, {args}) => (
      <Wrapper
        appPayload={{['enabled_features']: args}}
        routePayload={routePayload}
        pathname="/organizations/acme/settings/custom-properties"
        routes={[definitionsRoute]}
      >
        <Routes>
          <Route
            path={definitionsRoute.path}
            element={
              <BannerProvider>
                <Story />
              </BannerProvider>
            }
          />
        </Routes>
      </Wrapper>
    ),
  ],
}

export default meta

export const Default = {}

export const LimitReached = {
  parameters: {
    storyWrapper: {
      routePayload: {
        ...routePayload,
        definitions: Array.from({length: 101}, (v, i) => ({
          propertyName: `property-${i}`,
          valueType: 'string',
          required: false,
          defaultValue: null,
          description: null,
          allowedValues: null,
          valuesEditableBy: 'org_actors',
        })),
      },
    },
  },
}

export const OnlyDefinitionsPermission = {
  parameters: {
    storyWrapper: {
      routePayload: {
        ...routePayload,
        permissions: 'definitions',
      },
    },
  },
}

export const OnlyValuesPermission = {
  parameters: {
    storyWrapper: {
      routePayload: {
        ...routePayload,
        permissions: 'values',
      },
    },
  },
}
