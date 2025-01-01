// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {verifiedFetch} from '@github-ui/verified-fetch'
import type {SaveResponse} from '@github-ui/code-view-types'
import type {SafeHTMLString} from '@github-ui/safe-html'

export async function handleDelete(
  enterpriseSlug: string,
  selectedTeams: Set<string>,
  setFlash: (message: SafeHTMLString, isError: boolean) => void,
) {
  const formData = new FormData()
  for (const team of selectedTeams) {
    formData.append('team_slugs[]', team)
  }

  const result = await verifiedFetch(`/enterprises/${enterpriseSlug}/teams/bulk_delete`, {
    method: 'DELETE',
    headers: {Accept: 'application/json'},
    body: formData,
  })

  const json: SaveResponse = await result.json()
  if (json.data.redirect) {
    window.location.replace(json.data.redirect)
  } else if (json.data.error) {
    setFlash(json.data.error as SafeHTMLString, true)
  }
}
