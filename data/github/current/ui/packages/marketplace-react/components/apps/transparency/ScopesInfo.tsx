import {Banner} from '@primer/react/experimental'
import {Link, Text} from '@primer/react'

export function ScopesInfo() {
  return (
    <Banner
      data-testid="scopes-info"
      title="Info"
      hideTitle
      description={
        <>
          <Text weight="semibold">Note:</Text> OAuth Apps use scopes to grant access based on your current user
          permissions. You can view the specific scopes being requested before completing authorization. Scopes
          requested may change over time and depending on which resources you have access to. GitHub Apps use fixed,
          granular controls set at installation time.{' '}
          <Link
            inline
            href="https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps"
          >
            Learn more about OAuth and GitHub Apps
          </Link>
          .
        </>
      }
    />
  )
}
