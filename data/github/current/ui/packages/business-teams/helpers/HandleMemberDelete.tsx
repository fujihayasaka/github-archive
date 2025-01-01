import {verifiedFetch} from '@github-ui/verified-fetch'
import type {SaveResponse} from '@github-ui/code-view-types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {User} from '../types'

export async function handleMemberDelete(
  enterpriseSlug: string,
  teamSlug: string,
  members: User[],
  setFlash: (message: SafeHTMLString) => void,
) {
  const formData = new FormData()
  for (const member of members) {
    formData.append('user_ids[]', member.id.toString())
  }

  const result = await verifiedFetch(`/enterprises/${enterpriseSlug}/teams/${teamSlug}/members/bulk_delete`, {
    method: 'DELETE',
    headers: {Accept: 'application/json'},
    body: formData,
  })

  try {
    const json: SaveResponse = await result.json()
    if (json.data?.redirect) {
      window.location.replace(json.data.redirect)
    } else if (json.data?.error) {
      setFlash(json.data.error as SafeHTMLString)
    } else {
      setFlash('An error occurred while removing members.' as SafeHTMLString)
    }
  } catch {
    setFlash('An error occurred while removing members.' as SafeHTMLString)
  }
}
