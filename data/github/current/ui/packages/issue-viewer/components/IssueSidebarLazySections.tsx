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
import {DuplicateIssuesSection} from './sections/DuplicateIssuesSection'

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

export function IssueSidebarLazySections({
  issueSidebarSecondaryKey,
  onIssueUpdate,
  onLinkClick,
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
        ...DuplicateIssuesSectionFragment
      }
    `,
    issueSidebarSecondaryKey,
  )

  if (!data) {
    return <IssueSidebarLazySectionsFallback />
  }

  return (
    <>
      <RelationshipsSectionInternal issue={data} onLinkClick={onLinkClick} insideSidePanel={insideSidePanel} />
      <DevelopmentSection issue={data} onIssueUpdate={onIssueUpdate} />
      <DuplicateIssuesSection issue={data} />
      {isLoggedIn() && <SubscriptionSection issue={data} viewer={viewer} />}
      <ParticipantsSection issue={data} />
    </>
  )
}

export function IssueSidebarLazySectionsFallback() {
  return (
    <>
      <RelationshipsSectionFallback />
      <DevelopmentSectionFallback />
      {isLoggedIn() && <SubscriptionSectionFallback />}
    </>
  )
}
