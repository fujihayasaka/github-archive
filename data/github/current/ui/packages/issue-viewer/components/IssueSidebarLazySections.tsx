import {useFragment, graphql} from 'react-relay'
import {DevelopmentSection, DevelopmentSectionFallback} from './sections/development-section/DevelopmentSection'
import {SubscriptionSection, SubscriptionSectionFallback} from './sections/subscription-section/SubscriptionSection'
import type {IssueSidebarLazySections$key} from './__generated__/IssueSidebarLazySections.graphql'
import {ParticipantsSection} from './sections/ParticipantsSection'
import {
  RelationshipsSectionFallback,
  RelationshipsSectionInternal,
} from './sections/relations-section/RelationshipsSection'
import {isLoggedIn} from '@github-ui/client-env'
import type {IssueViewerViewer$data} from './__generated__/IssueViewerViewer.graphql'

type IssueSidebarLazySectionsBaseProps = {
  viewer: IssueViewerViewer$data | null
  onLinkClick?: (event: MouseEvent) => void
  onIssueUpdate?: () => void
  subIssuesEnabled?: boolean
  insideSidePanel?: boolean
}

type IssueSidebarLazySectionsProps = IssueSidebarLazySectionsBaseProps & {
  issueSidebarSecondaryKey?: IssueSidebarLazySections$key
}

type FallbackProps = {
  subIssuesEnabled?: boolean
}

export function IssueSidebarLazySections({
  issueSidebarSecondaryKey,
  onIssueUpdate,
  onLinkClick,
  subIssuesEnabled,
  insideSidePanel,
  viewer,
}: IssueSidebarLazySectionsProps) {
  const data = useFragment(
    graphql`
      fragment IssueSidebarLazySections on Issue {
        ...DevelopmentSectionFragment
        ...RelationshipsSectionFragment
        ...SubscriptionSectionFragment
        ...SubscriptionSectionRefetchableFragment
        ...ParticipantsSectionFragment
      }
    `,
    issueSidebarSecondaryKey,
  )

  if (!data) {
    return <IssueSidebarLazySectionsFallback subIssuesEnabled={subIssuesEnabled} />
  }

  return (
    <>
      {subIssuesEnabled && (
        <RelationshipsSectionInternal issue={data} onLinkClick={onLinkClick} insideSidePanel={insideSidePanel} />
      )}
      <DevelopmentSection issue={data} onIssueUpdate={onIssueUpdate} />
      {isLoggedIn() && <SubscriptionSection issue={data} viewer={viewer} />}
      <ParticipantsSection issue={data} />
    </>
  )
}

export function IssueSidebarLazySectionsFallback({subIssuesEnabled}: FallbackProps) {
  return (
    <>
      {subIssuesEnabled && <RelationshipsSectionFallback />}
      <DevelopmentSectionFallback />
      {isLoggedIn() && <SubscriptionSectionFallback />}
    </>
  )
}
