import {ActionList, ActionMenu, Link} from '@primer/react'
import {TEST_IDS} from '../../constants/test-ids'
import {OPEN_SOURCE_GUIDE_URL} from '../../constants/links'

export type FirstTimeContributionBannerDisplayProps = {
  repoNameWithOwner: string
  contributingGuidelinesUrl?: string
  hasGoodFirstIssueIssues: boolean
  contributeUrl: string
  dismissForThisRepo: () => void
  dismissForAllRepos: () => void
}

export const FirstTimeContributionBannerDisplay = ({
  repoNameWithOwner,
  contributingGuidelinesUrl,
  hasGoodFirstIssueIssues,
  contributeUrl,
  dismissForAllRepos,
  dismissForThisRepo,
}: FirstTimeContributionBannerDisplayProps) => {
  return (
    <div className="mt-2 p-4 text-center rounded-2 border color-border-muted">
      <div className="float-right">
        <ActionMenu>
          <ActionMenu.Button>Dismiss</ActionMenu.Button>
          <ActionMenu.Overlay width="medium">
            <ActionList>
              <ActionList.Item onSelect={dismissForThisRepo}>Dismiss for this repository only</ActionList.Item>
              <ActionList.Item onSelect={dismissForAllRepos}>Dismiss for all repositories</ActionList.Item>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </div>
      <div className="col-8 mx-auto">
        <h4 className="mb-2">👋 Want to contribute to {repoNameWithOwner}?</h4>
        <span>
          <span>If you have a bug or an idea, read the </span>
          <Link
            href={contributingGuidelinesUrl ?? OPEN_SOURCE_GUIDE_URL}
            target="_blank"
            data-testid={TEST_IDS.ftcBannerContributingGuidelinesLink}
          >
            contributing guidelines
          </Link>
          <span> before opening an issue. </span>
        </span>
        {hasGoodFirstIssueIssues && (
          <>
            <br />
            <span>
              <span>If you&apos;re ready to tackle some open issues, </span>
              <Link href={contributeUrl} target="_blank" data-testid="repo-good-first-issues">
                we&apos;ve collected some good first issues for you.
              </Link>
            </span>
          </>
        )}
      </div>
    </div>
  )
}
