import type {OrgCustomPropertiesPagePayload} from '@github-ui/custom-properties-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {SetValuesPage} from '../components/SetValuesPage'
import {CurrentOrgRepoProvider} from '../contexts/CurrentOrgRepoContext'
import {OrgCustomPropertiesListPage} from './OrgCustomPropertiesListPage'

export function OrgCustomPropertiesPage() {
  return (
    <CurrentOrgRepoProvider>
      <CustomPropertiesSchemaPageContent />
    </CurrentOrgRepoProvider>
  )
}

function CustomPropertiesSchemaPageContent() {
  const {activeTab} = useRoutePayload<OrgCustomPropertiesPagePayload>()

  return activeTab === 'set-values' ? <SetValuesPage /> : <OrgCustomPropertiesListPage />
}
