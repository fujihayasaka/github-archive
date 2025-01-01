import {useState} from 'react'
import {clsx} from 'clsx'
import {useQuery} from '@github-ui/react-query'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import useColorModes from '@github-ui/react-core/use-color-modes'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {Button, Heading, Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {Accordion} from '@github-ui/accordion'

import {AssessmentResultPage} from '../components/AssessmentResultPage'
import type {Assessment, Cost} from '../types'
import {queries, useCreateAssessmentMutation} from '../api'
import styles from './SecretRiskAssessmentPage.module.css'

export interface SecretRiskAssessmentPagePayload {
  help_url: string
  org: {
    login: string
  }
  assessment?: Assessment | null
  cost: Cost
  can_skip_rescan: boolean
  is_enterprise_or_mt: boolean
  show_enable_secret_protection_button: boolean
}

export function SecretRiskAssessmentPage({refetchInterval = 5000}: {refetchInterval?: number}) {
  // Guarantee `assessment` defaults to null (not undefined)
  // so `initialData` isn't considered unset and causes a query.
  const {
    help_url,
    org,
    assessment = null,
    cost,
    can_skip_rescan,
    is_enterprise_or_mt,
    show_enable_secret_protection_button,
  } = useRoutePayload<SecretRiskAssessmentPagePayload>()
  const {data, isError} = useQuery({
    ...queries.assessment(org.login),
    initialData: assessment,
    // Assessment is only gonna change if it's incomplete.
    staleTime: Infinity,
    refetchInterval: query => {
      // Stop polling if query fails 3 times.
      if (query.state.errorUpdateCount >= 3) {
        return false
      }
      const newAssessment = query.state.data
      if (!newAssessment || newAssessment?.is_complete) {
        return false
      }
      return refetchInterval
    },
  })

  if (!data) {
    return <LandingPage org={org.login} />
  }
  return (
    <>
      {isError && !data.is_complete && (
        <Banner
          className="mb-3"
          variant="critical"
          title="Error"
          description="Failed to update assessment progress. Please refresh the page, or try again later."
        />
      )}
      <AssessmentResultPage
        assessment={data}
        cost={cost}
        helpUrl={help_url}
        org={org.login}
        canSkipRescan={can_skip_rescan}
        isEnterpriseOrMT={is_enterprise_or_mt}
        showEnableSecretProtectionButton={show_enable_secret_protection_button}
      />
    </>
  )
}

function LandingPage({org}: {org: string}) {
  const mutation = useCreateAssessmentMutation({
    org,
  })

  const colorModes = useColorModes()
  const color = colorModes.colorMode === 'auto' ? 'day' : colorModes.colorMode
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  return (
    <>
      {mutation.isError && (
        <Banner
          variant="critical"
          title="Error"
          description="Failed to scan your organization. Please try again later."
          className="mb-3"
        />
      )}
      <div
        className="d-flex flex-justify-between p-4 mb-6 bgColor-muted border rounded-2"
        data-analytics-visible='{"category":"find-secrets-banner","action":"visible","group":"expand","location":"security-assessment-pre-scan"}'
      >
        <div className="col-sm-5">
          <h2 data-hpc>Find secrets exposed in your organization</h2>
          <p className="mb-3 fgColor-muted f5">
            Scan your organization now for free and receive a secret leaks audit with aggregate insights on any public
            leaks, leak sources, and token types.
          </p>
          <div className="d-flex flex-items-center gap-3">
            <Button
              variant="primary"
              onClick={() => {
                mutation.mutate()
                sendClickAnalyticsEvent({
                  location: 'security-assessment-pre-scan',
                  category: 'find-secrets-banner',
                  action: 'scan-organization',
                  tag: 'button',
                  group: 'expand',
                })
              }}
              loading={mutation.isPending}
              className="d-inline-flex flex-items-center gap-1"
            >
              Scan your organization
            </Button>
            <Link
              href="https://gh.io/ghsp-learn-more"
              onClick={() =>
                sendClickAnalyticsEvent({
                  location: 'security-assessment-pre-scan',
                  category: 'find-secrets-banner',
                  action: 'learn-more',
                  tag: 'button',
                  group: 'expand',
                })
              }
            >
              Learn more
            </Link>
          </div>
        </div>
        <img
          className={clsx(styles.startScanBannerImage, 'mr-n4 mb-n4')}
          src={`/images/secret-scanning/risk-assessment/start_scan_banner--${color}.png`}
          alt=""
        />
      </div>
      <FAQ />
    </>
  )
}

function FAQ() {
  const [expandedItems, setExpandedItems] = useState<string[]>([])

  const contentClass = clsx('fgColor-muted', styles.maxWidthMedium)
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  return (
    <div className="d-flex flex-column gap-3 px-5">
      <Heading as="h2" variant="medium">
        Frequently asked questions
      </Heading>
      <Accordion expandedItems={expandedItems} onChange={setExpandedItems}>
        <Accordion.Item value="section-1">
          <Accordion.Trigger className="pt-0">
            <h3 className="f4">What happens once I start the scan?</h3>
          </Accordion.Trigger>
          <Accordion.Content className={contentClass}>
            GitHub will perform a point-in-time scan of all repositories in your organization, reporting back helpful
            insights like count of secrets leaked per type. No specific secrets will be stored or shared.
          </Accordion.Content>
        </Accordion.Item>
        <Accordion.Item value="section-2">
          <Accordion.Trigger>
            <h3 className="f4">How will I be notified?</h3>
          </Accordion.Trigger>
          <Accordion.Content className={contentClass}>
            GitHub will notify you via email when the report is complete. If you’ve previously opted in to marketing or
            sales-based communication from GitHub, you may receive additional content about the report.
          </Accordion.Content>
        </Accordion.Item>
        <Accordion.Item value="section-3">
          <Accordion.Trigger>
            <h3 className="f4">What is the cost of a leaked secret?</h3>
          </Accordion.Trigger>
          <Accordion.Content className={contentClass}>
            A single exposed secret can lead to a comprehensive breach, potentially costing millions in addition to
            untold damage to an organization&apos;s reputation. Learn more about secret leaks and how to reduce your
            risk of exposures by{' '}
            <Link
              inline
              href="https://github.com/resources/whitepapers/secret-scanning-a-key-to-your-cybersecurity-strategy"
              onClick={() => {
                sendClickAnalyticsEvent({
                  location: 'security-assessment-pre-scan',
                  category: 'faq',
                  action: 'reading',
                  tag: 'link',
                })
              }}
            >
              reading
            </Link>
            ,{' '}
            <Link
              inline
              href="https://www.youtube.com/watch?v=vMhDkt5JNN0"
              onClick={() => {
                sendClickAnalyticsEvent({
                  location: 'security-assessment-pre-scan',
                  category: 'faq',
                  action: 'watching',
                  tag: 'link',
                })
              }}
            >
              watching
            </Link>
            , or{' '}
            <Link
              inline
              href="https://resources.github.com/topics/github-advanced-security/"
              onClick={() => {
                sendClickAnalyticsEvent({
                  location: 'security-assessment-pre-scan',
                  category: 'faq',
                  action: 'exploring',
                  tag: 'link',
                })
              }}
            >
              exploring
            </Link>
            .
          </Accordion.Content>
        </Accordion.Item>
      </Accordion>
    </div>
  )
}
