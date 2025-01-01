import {createQuery} from 'react-query-kit'

import {apiGetCustomTemplates} from '../api/memex/api-get-custom-templates'
import type {GetCustomTemplatesResponse} from '../api/memex/contracts'

export const useOrganizationTemplates = createQuery<GetCustomTemplatesResponse>({
  queryKey: ['memex', 'org-templates'],
  fetcher: () => apiGetCustomTemplates(),
})
