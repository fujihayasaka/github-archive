import {useMutation, useQuery} from '@github-ui/react-query'

import {Service, useWorkbenchStore} from '../contexts/WorkbenchStoreContext'

export const useModifyJsxClassName = (serverUrl: string, tunnelToken: string) => {
  const {onError, onSuccess} = useWorkbenchStore()
  return useMutation({
    mutationFn: async (data: {
      filePath: string
      line: number
      column: number
      className: string
      replace?: boolean
    }) => {
      const response = await fetch(`${serverUrl}/jsx/class-name`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json', 'X-Tunnel-Authorization': `tunnel ${tunnelToken}`},
        body: JSON.stringify(data),
      })
      if (!response.ok) {
        onError({service: Service.DESIGNER})
        throw new Error('Network response was not ok')
      }
      onSuccess({service: Service.DESIGNER})
      return response.json()
    },
  })
}

export const useModifyJsxText = (serverUrl: string, tunnelToken: string) => {
  const {onError, onSuccess} = useWorkbenchStore()
  return useMutation({
    mutationFn: async (data: {filePath: string; line: number; column: number; content: string}) => {
      const response = await fetch(`${serverUrl}/jsx/text`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json', 'X-Tunnel-Authorization': `tunnel ${tunnelToken}`},
        body: JSON.stringify(data),
      })
      if (!response.ok) {
        onError({service: Service.DESIGNER})
        throw new Error('Network response was not ok')
      }
      onSuccess({service: Service.DESIGNER})
      return response.json()
    },
  })
}

export const useModifyGlobalCssVariable = (serverUrl: string, tunnelToken: string) => {
  const {onError, onSuccess} = useWorkbenchStore()
  return useMutation({
    mutationFn: async (data: {name: string; value: string}) => {
      const response = await fetch(`${serverUrl}/css/global-variable`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json', 'X-Tunnel-Authorization': `tunnel ${tunnelToken}`},
        body: JSON.stringify(data),
      })
      if (!response.ok) {
        onError({service: Service.DESIGNER})
        throw new Error('Network response was not ok')
      }
      onSuccess({service: Service.DESIGNER})
      return response.json()
    },
  })
}

export type ThemeVariables = {
  accent: string
  'accent-foreground': string
  background: string
  border: string
  card: string
  'card-foreground': string
  destructive: string
  'destructive-foreground': string
  foreground: string
  input: string
  muted: string
  'muted-foreground': string
  popover: string
  'popover-foreground': string
  primary: string
  'primary-foreground': string
  ring: string
  secondary: string
  'secondary-foreground': string
  radius: string
  spacing: string
}

export const useGetThemeVariables = (serverUrl: string, tunnelToken: string) => {
  return useQuery({
    // eslint-disable-next-line @tanstack/query/exhaustive-deps
    queryKey: ['theme-variables'],
    queryFn: async () => {
      const response = await fetch(`${serverUrl}/css/theme`, {
        headers: {'X-Tunnel-Authorization': `tunnel ${tunnelToken}`},
      })
      if (!response.ok) throw new Error('Network response was not ok')
      const {variables} = (await response.json()) as {variables: ThemeVariables}
      return variables
    },
    enabled: !!serverUrl && !!tunnelToken,
  })
}

export const useModifyThemeVariables = (serverUrl: string, tunnelToken: string) => {
  return useMutation({
    mutationFn: async (data: {updates: Array<{name: string; value: string}>}) => {
      const response = await fetch(`${serverUrl}/css/theme`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json', 'X-Tunnel-Authorization': `tunnel ${tunnelToken}`},
        body: JSON.stringify(data),
      })
      if (!response.ok) throw new Error('Network response was not ok')
      return response.json()
    },
  })
}
