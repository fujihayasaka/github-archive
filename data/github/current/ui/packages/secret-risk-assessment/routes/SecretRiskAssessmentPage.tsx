import {useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useMutation} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {LinkExternalIcon} from '@primer/octicons-react'
import {Button, Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import {AssessmentResultPage} from '../components/AssessmentResultPage'
import type {Assessment} from '../types'
import {riskAssessmentPath} from '../paths'

export interface SecretRiskAssessmentPagePayload {
  help_url: string
  org: {
    login: string
  }
  assessment?: Assessment
}

export function SecretRiskAssessmentPage() {
  const {help_url, org, assessment} = useRoutePayload<SecretRiskAssessmentPagePayload>()
  const [createdAssessment, setCreatedAssessment] = useState<Assessment | null>(null)

  const currentAssessment = assessment || createdAssessment

  if (!currentAssessment) {
    return (
      <LandingPage
        scanPath={riskAssessmentPath(org.login)}
        onScan={() => {
          const date = new Date()
          date.setDate(date.getDate() + 90)
          setCreatedAssessment({
            can_request_another_assessment: false,
            next_request_available_at: date.toISOString(),
            last_status_change: date.toISOString(),
            is_complete: false,
            total_scans_wanted: 1,
            total_scans_completed: 0,
            total_tokens_found: 0,
            total_tokens_found_in_public_repo: 0,
            total_tokens_found_push_protected_patterns: 0,
            total_tokens_found_non_provider_patterns: 0,
            tokens: [],
          })
        }}
      />
    )
  }
  return <AssessmentResultPage assessment={currentAssessment} helpUrl={help_url} />
}

function LandingPage({scanPath, onScan}: {scanPath: string; onScan: () => void}) {
  const mutation = useMutation({
    mutationFn: async () => {
      const res = await reactFetchJSON(scanPath, {method: 'POST'})
      if (!res.ok) {
        throw new Error(`Failed to start assessment, status: ${res.status}`)
      }
      onScan()
    },
  })
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
      <div className="d-flex flex-justify-between p-4 mb-3 bgColor-muted border rounded-2">
        <div>
          <h2 data-hpc>Find secrets being exposed in your organization</h2>
          <p className="fgColor-muted f5">
            Scan your organization with GitHub Secret Protection to find public leaks, leak sources, and token types —
            free for all organizations.
          </p>
          <div className="d-flex flex-items-center gap-3">
            <Button
              variant="primary"
              onClick={() => mutation.mutate()}
              loading={mutation.isPending}
              className="d-inline-flex flex-items-center gap-1"
            >
              Scan your organization
            </Button>
            <Link href="https://gh.io/ghsp-learn-more">Learn more</Link>
          </div>
        </div>
        <span>TODO graphic/banner</span>
      </div>
      <div className="d-flex gap-3">
        <LandingCard
          title="What are secrets?"
          body="Secrets are sensitive information used to authenticate, authorize, and encrypt data within an application or system. Examples include passwords, API tokens, SSH keys, and tokens."
        />
        <LandingCard
          title="How can secrets be exploited?"
          body="Secrets are usually the first step for bad actors to launch broader attacks, leveraging tactics such as data theft, ransomware, cloud environment exploitation, and supply chain attacks."
        />
        <LandingCard
          title="What is the cost of a leaked secret?"
          body="A single exposed secret can lead to a comprehensive breach, potentially costing millions in addition to untold damage to an organization's reputation."
        >
          <Link href="https://gh.io/secret-protection-roi" target="_blank" className="f6">
            View the ROI calculator
            <LinkExternalIcon />
          </Link>
        </LandingCard>
      </div>
    </>
  )
}

function LandingCard({title, body, children}: {title: string; body: string; children?: React.ReactNode}) {
  return (
    <div className="p-3 border rounded-2">
      <p className="h5">{title}</p>
      <p className="fgColor-muted f6">{body}</p>
      {children}
    </div>
  )
}
