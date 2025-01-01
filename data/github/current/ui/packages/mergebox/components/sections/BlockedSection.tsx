import {Link, Text} from '@primer/react'
import {AlertIcon} from './common/AlertIcon'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import type {FailingRulesAndConditionPayload} from '../../types'

export interface BlockedSectionProps {
  failingConditionsAndRules: FailingRulesAndConditionPayload[]
}

/**
 *
 * Describes why a pull request is unmergeable
 *
 * If the pull request is unmergeable, this component will render a section describing why
 */
export function BlockedSection({failingConditionsAndRules}: BlockedSectionProps) {
  return (
    <section aria-label="Merging is blocked" className="border-bottom borderColor-muted">
      <MergeBoxSectionHeader title="Merging is blocked" icon={<AlertIcon bgColor="danger.emphasis" />}>
        <ul className="list-style-none">
          {failingConditionsAndRules.map(
            condition =>
              condition &&
              'message' in condition && (
                <Text key={condition.displayName} as="li" sx={{color: 'fg.muted', mb: 0}}>
                  <SafeHTMLText html={(condition.message || '') as SafeHTMLString} />{' '}
                  <AdditionalMessaging ruleName={condition.displayName} />
                </Text>
              ),
          )}
        </ul>
      </MergeBoxSectionHeader>
    </section>
  )
}

function AdditionalMessaging({ruleName}: {ruleName: string}) {
  if (ruleName === 'UNVERIFIED_EMAIL') {
    return (
      <>
        You will be able to merge this pull request after you{' '}
        <Link href="/settings/emails" inline>
          verify your email address
        </Link>
        .
      </>
    )
  }

  return null
}
