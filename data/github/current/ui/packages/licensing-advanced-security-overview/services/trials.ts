import {verifiedFetchJSON} from '@github-ui/verified-fetch'

type StartTrialResponse = {error?: string}
export async function startTrial(basePath: string): Promise<void> {
  const response = await verifiedFetchJSON(`${basePath}/settings/advanced_security/trials`, {
    method: 'POST',
  })
  const result = (await response.json()) as StartTrialResponse
  if (!result) {
    throw new Error('Failed to start trial')
  }
  if ('error' in result) {
    throw new Error(result.error)
  }
}
