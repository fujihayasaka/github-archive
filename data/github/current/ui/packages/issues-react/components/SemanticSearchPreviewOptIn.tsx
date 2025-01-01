import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Button, Label, Link, Stack} from '@primer/react'
import {useCallback} from 'react'

export function SemanticSearchPreviewOptIn(): JSX.Element | undefined {
  const issuesSemanticSearchPreviewOptIn = useFeatureFlag('issues_semantic_search_preview_opt_in')
  const issuesSemanticSearchPreviewEnabled = useFeatureFlag('issues_semantic_search_preview_enabled')

  const onOptInOptOut = useCallback(async () => {
    const optIn = issuesSemanticSearchPreviewOptIn && !issuesSemanticSearchPreviewEnabled
    await verifiedFetchJSON(`${window.location.pathname}?issues_semantic_search=${optIn}`, {method: 'POST'})
    window.location.reload()
  }, [issuesSemanticSearchPreviewEnabled, issuesSemanticSearchPreviewOptIn])

  if (!issuesSemanticSearchPreviewEnabled && !issuesSemanticSearchPreviewOptIn) {
    return undefined
  }

  return (
    <Stack data-testid="issues-semantic-search-preview-opt-in" gap="condensed" direction="horizontal">
      <Label variant="accent">Staff</Label>
      <Button className="text-normal" variant="link" onClick={onOptInOptOut}>
        {issuesSemanticSearchPreviewEnabled ? 'Opt out of the new semantic search' : 'Try the new semantic search'}
      </Button>
      <span>•</span>
      <Link href="https://gh.io/AAvd45k">{issuesSemanticSearchPreviewEnabled ? 'Give feedback' : 'Learn more'}</Link>
    </Stack>
  )
}
