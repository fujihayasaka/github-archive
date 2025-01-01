import {Stack} from '@primer/react'
import type {AppListing} from '@github-ui/marketplace-common'
import {
  CommentDiscussionIcon,
  ReportIcon,
  BookIcon,
  LawIcon,
  PulseIcon,
  RepoIcon,
  TagIcon,
} from '@primer/octicons-react'
import {useMemo} from 'react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {reportAbusePath} from '@github-ui/paths'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {ResourceList} from '../../sidebar-shared/ResourceList'
import {useClientValue} from '@github-ui/use-client-value'

type ResourcesProps = {
  app: AppListing
}

export function Resources({app}: ResourcesProps) {
  const [reportPath] = useClientValue(
    () => {
      const host = ssrSafeLocation?.origin
      if (!host) return undefined
      const listingUrl = `${host}/marketplace/${app.slug}`

      return reportAbusePath({report: `${listingUrl} (Marketplace Listing)`})
    },
    undefined,
    [ssrSafeLocation?.origin, app.slug],
  )

  const linkItems = useMemo(
    () => [
      {
        url: app.supportUrl || (app.supportEmail && `mailto:${app.supportEmail}`),
        component: CommentDiscussionIcon,
        text: 'Support',
      },
      {url: app.pricingUrl, component: TagIcon, text: 'Pricing'},
      {url: app.repositoryUrl, component: RepoIcon, text: 'Repository'},
      {url: app.documentationUrl, component: BookIcon, text: 'Documentation'},
      {url: app.privacyPolicyUrl, component: LawIcon, text: 'Privacy Policy'},
      {url: app.tosUrl, component: LawIcon, text: 'Terms of Service'},
      {url: app.statusUrl, component: PulseIcon, text: 'Status'},
      {
        url: reportPath,
        component: ReportIcon,
        text: 'Report abuse',
      },
    ],
    [app, reportPath],
  )
  return (
    <Stack gap={'condensed'} data-testid="apps-resources">
      <SidebarHeading title="Resources" htmlTag={'h2'} />
      <ResourceList linkItems={linkItems} />
    </Stack>
  )
}
