import {verifiedFetch} from '@github-ui/verified-fetch'
import type {Organization} from '../types'
import type {SafeHTMLString} from '@github-ui/safe-html'

export async function handleOrgDelete(
  enterpriseSlug: string,
  teamSlug: string,
  orgs: Organization[],
  setFlash: (message: SafeHTMLString) => void,
) {
  const formData = new FormData()
  for (const org of orgs) {
    formData.append('organization_ids[]', org.id.toString())
  }

  const result = await verifiedFetch(`/enterprises/${enterpriseSlug}/teams/${teamSlug}/organizations/bulk_delete`, {
    method: 'DELETE',
    headers: {Accept: 'application/json'},
    body: formData,
  })

  try {
    const json = await result.json()
    if (json.message) {
      return json
    } else if (json.error) {
      setFlash(json.error)
      return
    }
    setFlash(`Failed to delete organizations from team ${teamSlug}` as SafeHTMLString)
  } catch {
    setFlash(`Failed to delete organizations from team ${teamSlug}` as SafeHTMLString)
  }
}
