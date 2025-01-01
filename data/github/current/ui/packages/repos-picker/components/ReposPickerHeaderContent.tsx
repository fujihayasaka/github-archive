import {useQuery} from '@github-ui/react-query'
import {ReposFilter} from '@github-ui/repos-filter'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Dialog} from '@primer/react'
import type {RefObject} from 'react'

import {reposPickerDefinitionsPath} from '../paths'
import type {PropertyDefinition} from '../types'

interface ReposPickerHeaderContentProps {
  inputRef?: RefObject<HTMLInputElement>
  initialQuery?: string
  dialogTitle: string
  orgLogin: string | undefined
  onDismiss: () => void
  setQuery: (newQuery: string) => void
  allowedProviders?: React.ComponentProps<typeof ReposFilter>['allowedProviders']
}

const DEFINITIONS_STALE_TIME_IN_MS = 1000 * 60 * 5 // 5 minutes

export function ReposPickerHeaderContent({
  dialogTitle,
  orgLogin,
  initialQuery = '',
  onDismiss,
  setQuery,
  inputRef,
  allowedProviders,
}: ReposPickerHeaderContentProps) {
  const {data: definitions} = useQuery<PropertyDefinition[]>({
    queryKey: ['repos-picker', 'definitions', orgLogin],
    enabled: !!orgLogin,
    queryFn: async () => {
      const fetchDefinitionsUrl = reposPickerDefinitionsPath({orgLogin: orgLogin!})

      const response = await verifiedFetchJSON(fetchDefinitionsUrl)
      if (!response.ok) return []

      const responseData = await response.json()
      return responseData.definitions
    },
    staleTime: DEFINITIONS_STALE_TIME_IN_MS,
  })

  return (
    <div className="p-2 border-bottom">
      <div className="d-flex px-2">
        <div className="d-flex flex-1 pt-2">
          <Dialog.Title>{dialogTitle}</Dialog.Title>
        </div>
        <Dialog.CloseButton onClose={() => onDismiss()} />
      </div>
      <ReposFilter
        className="p-2"
        id="repos-filter"
        inputRef={inputRef}
        initialFilterValue={initialQuery}
        definitions={definitions ?? []}
        label="Filter repositories"
        variant="input"
        onSubmit={({raw}) => setQuery(raw)}
        allowedProviders={allowedProviders}
      />
    </div>
  )
}
