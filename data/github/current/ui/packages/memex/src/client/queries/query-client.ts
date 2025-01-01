import {getQueryClient} from '@github-ui/react-core/query-client'

export const queryClient = getQueryClient()

queryClient.setQueryDefaults(['memex'], {retry: 1})
