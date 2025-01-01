import type {DependabotAutomatedSecurityUpdates, HeaderPageData} from '../../page-data/payloads/header'
import {Banner} from '@primer/react/experimental'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'

import {PullRequestAutomatedSecurityOnboarding} from './PullRequestAutomatedSecurityOnboarding'

export function PullRequestAutomatedSecurityUpdateBanner({
  dependabotUpdates,
  pullRequest,
}: {
  dependabotUpdates: DependabotAutomatedSecurityUpdates
  pullRequest: HeaderPageData['pullRequest']
}) {
  const openPullRequestLead = 'Merging this pull request will resolve'

  const nonOpenPullRequestLead = 'This pull request'

  const nonAlertText = 'a Dependabot alert'

  const linkBuilder = (linkText: string) => {
    // eslint-disable-next-line github/unescaped-html-literal
    return `<a class="Link Link--underline" href=${dependabotUpdates.securityAlertPath}>${linkText}</a>`
  }

  // eslint-disable-next-line github/unescaped-html-literal
  const boldText = (text: string) => `<strong>${text}</strong>`

  const linkText = () => {
    if (dependabotUpdates.alertPresent) {
      if (dependabotUpdates.singleAlert) {
        const htmlString = (`${openPullRequestLead} a ${boldText(dependabotUpdates.severity)} severity` +
          ` ${linkBuilder('Dependabot Alert')} on ${dependabotUpdates.packageName}`) as SafeHTMLString
        return <SafeHTMLText as="span" html={htmlString} />
      } else {
        const htmlString = (`${openPullRequestLead} ${linkBuilder('Dependabot Alerts')} on` +
          ` ${dependabotUpdates.packageName} including a` +
          ` ${boldText(dependabotUpdates.severity)} severity alert`) as SafeHTMLString
        return <SafeHTMLText as="span" html={htmlString} />
      }
    } else {
      return `${openPullRequestLead} ${nonAlertText}`
    }
  }

  const properTense = () => {
    if (pullRequest.state === 'MERGED') {
      return 'resolved'
    } else {
      return 'would resolve'
    }
  }

  const closingText = () => {
    if (dependabotUpdates.alertPresent) {
      return `a Dependabot alert on ${dependabotUpdates.packageName}.`
    } else {
      return nonAlertText
    }
  }

  const displayText = () => {
    if (pullRequest.state === 'OPEN') {
      return linkText()
    } else {
      return `${nonOpenPullRequestLead} ${properTense()} ${closingText()}`
    }
  }

  return (
    <div className="width-full">
      <Banner aria-label="Automated Security Update Banner" variant="info" title="Automated security update" hideTitle>
        <Banner.Description>{displayText()}</Banner.Description>
      </Banner>
      {dependabotUpdates.showOnboardingPopover && (
        <PullRequestAutomatedSecurityOnboarding onBoardingProps={dependabotUpdates.onboardingBannerProps} />
      )}
    </div>
  )
}
