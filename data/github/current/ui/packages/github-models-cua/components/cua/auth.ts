import React from 'react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import safeStorage from '@github-ui/safe-storage'

type Tokens = {cua: string; github: string}

export function useAuthToken(): Promise<Tokens> {
  // @ts-expect-error yeah yeah
  const {auth_token} = useAppPayload()

  return React.useState<Promise<Tokens>>(async () => {
    const {getItem} = safeStorage('localStorage')

    const cua_token = getItem('models_cua_token_override') || 'UNKNOWN'
    const github_token = getItem('models_github_token_override') || auth_token
    return {cua: cua_token, github: github_token}
  }).at(0) as Promise<Tokens>
}
