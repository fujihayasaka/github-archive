import React from 'react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'

type Tokens = {cua: string; github: string}

export function useAuthToken(): Promise<Tokens> {
  // @ts-expect-error yeah yeah
  const {auth_token} = useAppPayload()

  return React.useState<Promise<Tokens>>(async () => {
    const cua_token = localStorage['models_cua_token_override'] || 'UNKNOWN'
    const github_token = localStorage['models_github_token_override'] || auth_token
    return {cua: cua_token, github: github_token}
  }).at(0) as Promise<Tokens>
}
