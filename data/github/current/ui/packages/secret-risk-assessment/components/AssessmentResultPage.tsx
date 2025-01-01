import {useId, useRef, useState, type ReactNode} from 'react'
import {clsx} from 'clsx'
import DataCard from '@github-ui/data-card'
import {
  CheckIcon,
  KeyIcon,
  KebabHorizontalIcon,
  SyncIcon,
  DotFillIcon,
  InfoIcon,
  XIcon,
  DownloadIcon,
} from '@primer/octicons-react'
import {
  ActionList,
  ActionMenu,
  AnchoredOverlay,
  Button,
  Dialog,
  IconButton,
  Link,
  RelativeTime,
  Spinner,
} from '@primer/react'
import {Banner, DataTable, Table, type Column} from '@primer/react/experimental'
import useColorModes from '@github-ui/react-core/use-color-modes'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useMutation, useQuery} from '@github-ui/react-query'
// eslint-disable-next-line no-restricted-imports
import {toPercentInt} from '@github-ui/secret-scanning/utils'
import type {Assessment, Cost, TokenTypeLocaleResult} from '../types'
import styles from './AssessmentResultPage.module.css'
import {downloadResultsCSVPath, enableGhspPath, hasConfigConflict} from '../paths'
import {useCreateAssessmentMutation} from '../api'
import {useClickAnalytics} from '@github-ui/use-analytics'

export function AssessmentResultPage({
  assessment,
  cost,
  helpUrl,
  org,
  canSkipRescan,
  isEnterpriseOrMT,
  showEnableSecretProtectionButton = true,
}: {
  assessment: Assessment
  cost: Cost
  helpUrl: string
  org: string
  canSkipRescan?: boolean
  isEnterpriseOrMT?: boolean
  showEnableSecretProtectionButton?: boolean
}) {
  const [pageIndex, setPageIndex] = useState(0)
  const pageSize = 15
  const start = pageIndex * pageSize
  const end = start + pageSize
  const data: TokenTypeLocaleResult[] = assessment.tokens.slice(start, end).map(item => ({
    ...item,
    distinct_repos_count: item.distinct_repos_count.toLocaleString(),
    unique_tokens_found_count: item.unique_tokens_found_count.toLocaleString(),
  }))

  const columns: Array<Column<TokenTypeLocaleResult>> = [
    {
      header: 'Secret type',
      field: 'name',
    },
    {
      header: 'Distinct repositories',
      field: 'distinct_repos_count',
      align: 'end',
    },
    {
      header: 'Secrets found',
      field: 'unique_tokens_found_count' as const,
      align: 'end',
      // TODO get sorting working properly
      // sortBy: true,
    },
  ]

  const mutation = useCreateAssessmentMutation({
    org,
  })

  const noLeaks = assessment.is_complete && assessment.total_tokens_found === 0

  const colorModes = useColorModes()
  const color = colorModes.colorMode === 'auto' ? 'day' : colorModes.colorMode
  const dataCardClass = 'flex-basis-full md:flex-basis-auto'
  const dataTableId = useId()

  const pctComplete = toPercentInt(assessment.total_scans_completed, assessment.total_scans_wanted, {floor: true})
  const assessmentInQueuedState = pctComplete === 0 && !assessment.is_complete

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  return (
    <div className="d-flex flex-column gap-3">
      {mutation.isError && (
        <Banner variant="critical" title="Error" description="Failed to rerun scan. Please try again later." />
      )}
      {noLeaks && showEnableSecretProtectionButton && (
        <UpsellBanner
          cost={cost}
          buttonVariant="primary"
          renderBanner={enableButtons => <NoLeaksBanner enableButtons={enableButtons} color={color} />}
          successBanner={<NoLeaksSuccessBanner color={color} />}
          org={org}
          helpUrl={helpUrl}
          noLeaks={noLeaks}
          showPublicRepoOption={!isEnterpriseOrMT}
          showEnableSecretProtectionButton={showEnableSecretProtectionButton}
        />
      )}
      <div>
        <div className="d-flex flex-justify-between">
          <div>
            <h2 className="h3 d-inline-block mr-2" data-hpc>
              Secrets in your organization
            </h2>
            {!isEnterpriseOrMT && (
              <Link className="text-small" href="https://gh.io/github-feedback-on-secrets">
                Give feedback
              </Link>
            )}
          </div>
          <div className="d-flex flex-items-center gap-2">
            {assessment.is_complete ? (
              <span>
                <CheckIcon className="fgColor-success mr-2" />
                Scan completed
              </span>
            ) : (
              <>
                <Spinner size="small" />
                <span>{pctComplete > 0 ? `Scan ${pctComplete}% complete` : 'Queued to start'}</span>
              </>
            )}
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton
                  aria-label="More assessment options"
                  icon={KebabHorizontalIcon}
                  data-testid="assessment-more-options"
                />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay>
                <ActionList>
                  <ActionList.Item
                    loading={mutation.isPending}
                    onSelect={e => {
                      if (!assessment.can_request_another_assessment && !canSkipRescan) {
                        // Prevent dropdown from collapsing, then no-op
                        e.preventDefault()
                        return
                      }
                      mutation.mutate()
                    }}
                  >
                    <ActionList.LeadingVisual>
                      <SyncIcon />
                    </ActionList.LeadingVisual>
                    Rerun scan
                    <ActionList.Description variant="block" className="fgColor-attention">
                      {/*
                        https://github.com/github/relative-time-element?tab=readme-ov-file#cheatsheet
                        Setting tense="future" makes it so that datetimes that are behind the current date
                        will show as "now". E.g., a run that became available 5 min ago will show as
                        "Next run available now".
                      */}
                      Next run available <RelativeTime tense="future" datetime={assessment.next_request_available_at} />
                    </ActionList.Description>
                  </ActionList.Item>
                  {assessment.is_complete && (
                    <ActionList.LinkItem
                      href={downloadResultsCSVPath(org)}
                      onClick={() => {
                        sendClickAnalyticsEvent({
                          location: 'security-assessment-post-scan',
                          category: 'assessment-results-menu',
                          action: 'download-csv',
                          tag: 'link',
                        })
                      }}
                    >
                      <ActionList.LeadingVisual>
                        <DownloadIcon />
                      </ActionList.LeadingVisual>
                      Download CSV
                    </ActionList.LinkItem>
                  )}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </div>
        </div>
        <p className="fgColor-muted f5">
          Insights across all repositories in your organization for audit started{' '}
          <RelativeTime datetime={assessment.requested_at} />.
        </p>
      </div>
      {!assessment.is_complete && <ScanInProgressBanner />}
      {assessment.is_complete && !showEnableSecretProtectionButton && <ContactAdministratorBanner />}
      {assessment.is_complete && !noLeaks && showEnableSecretProtectionButton && (
        <UpsellBanner
          cost={cost}
          renderBanner={enableButtons => <AssessmentResultBanner enableButtons={enableButtons} />}
          successBanner={
            <Banner
              variant="success"
              icon={<KeyIcon />}
              title="Settings applied"
              data-analytics-visible='{"category":"protection-applied-banner","action":"visible","group":"expand","location":"security-assessment-post-scan"}'
              description={
                <>
                  <p>
                    GitHub Secret Protection is enabled for your organization. For very large organizations, this may
                    take some time to complete. As for now, treat yourself — you did good today. ✨
                  </p>
                </>
              }
            />
          }
          org={org}
          helpUrl={helpUrl}
          noLeaks={noLeaks}
          showPublicRepoOption={!isEnterpriseOrMT}
          showEnableSecretProtectionButton={showEnableSecretProtectionButton}
        />
      )}
      <div className="d-flex flex-justify-between flex-wrap md:flex-nowrap gap-3">
        <DataCard className={dataCardClass} cardTitle="Total secrets" loading={assessmentInQueuedState}>
          <DataCard.Counter count={assessment.total_tokens_found} />
          <DataCard.Description>Secret leaks found across your organization repositories.</DataCard.Description>
        </DataCard>
        <DataCard className={dataCardClass} cardTitle="Public leaks" loading={assessmentInQueuedState}>
          <DataCard.Counter count={assessment.total_tokens_found_in_public_repo} />
          <DataCard.Description>Distinct secrets found in your public repositories.</DataCard.Description>
        </DataCard>
        {!noLeaks ? (
          <DataCard className={dataCardClass} cardTitle="Preventable leaks" loading={assessmentInQueuedState}>
            <DataCard.Counter count={assessment.total_tokens_found_push_protected_patterns} />
            <DataCard.Description>
              Secrets which could have been prevented with{' '}
              <Link href={`${helpUrl}/code-security/secret-scanning/introduction/about-push-protection`} inline>
                push protection
              </Link>
              .
            </DataCard.Description>
          </DataCard>
        ) : (
          <>
            <DataCard className={dataCardClass} cardTitle="Repositories scanned" loading={assessmentInQueuedState}>
              <DataCard.Counter count={assessment.distinct_repos_scanned} />
              <DataCard.Description>Repositories scanned across your organization on GitHub.</DataCard.Description>
            </DataCard>
          </>
        )}
      </div>
      <div className="d-flex flex-justify-between flex-wrap md:flex-nowrap gap-3">
        {/* TODO: Make the colors dynamically synced with the ProgressBar component rather than hard coded */}
        <DataCard className={dataCardClass} cardTitle="Secret locations" loading={assessmentInQueuedState}>
          <DataCard.ProgressBar data={[{progress: 100, label: 'Code'}]} />
          <div className="d-flex flex-wrap gap-2 mb-1">
            <ProgressCardItem
              label="Code"
              labelColor="fgColor-accent"
              data={{count: assessment.total_tokens_found, total: assessment.total_tokens_found}}
            />
            <ProgressCardItem label="Issues" labelColor="fgColor-muted" />
            <ProgressCardItem label="Wikis" labelColor="fgColor-muted" />
            <ProgressCardItem label="Pull requests" labelColor="fgColor-muted" />
          </div>
          <p className="fgColor-muted f6">
            Continuously scan additional locations outside of git history with{' '}
            <Link href={`${helpUrl}/code-security/secret-scanning`} inline>
              secret scanning
            </Link>
            .
          </p>
        </DataCard>
        <DataCard
          className={dataCardClass}
          cardTitle={
            <div className="d-flex flex-items-center gap-1">
              <span>Secret categories</span>
              <InfoOverlay helpUrl={helpUrl} />
            </div>
          }
          loading={assessmentInQueuedState}
        >
          <DataCard.ProgressBar
            data={[
              {
                progress:
                  (100 * (assessment.total_tokens_found - assessment.total_tokens_found_non_provider_patterns)) /
                  assessment.total_tokens_found,
                label: 'Provider patterns',
              },
              {
                progress: (100 * assessment.total_tokens_found_non_provider_patterns) / assessment.total_tokens_found,
                label: 'Generic patterns',
              },
            ]}
          />
          <div className="d-flex flex-wrap gap-2 mb-1">
            <ProgressCardItem
              label="Provider patterns"
              labelColor="fgColor-accent"
              data={{
                count: assessment.total_tokens_found - assessment.total_tokens_found_non_provider_patterns,
                total: assessment.total_tokens_found,
              }}
            />
            <ProgressCardItem
              label="Generic patterns"
              labelColor="fgColor-success"
              data={{count: assessment.total_tokens_found_non_provider_patterns, total: assessment.total_tokens_found}}
            />
          </div>
          <p className="fgColor-muted f6">
            Scan additional secret types with{' '}
            <Link href={`${helpUrl}/code-security/secret-scanning/copilot-secret-scanning`} inline>
              Copilot AI-detection
            </Link>{' '}
            and{' '}
            <Link
              href={`${helpUrl}/code-security/secret-scanning/using-advanced-secret-scanning-and-push-protection-features/custom-patterns`}
              inline
            >
              custom patterns
            </Link>
            .
          </p>
        </DataCard>
        {!noLeaks && (
          <DataCard className={dataCardClass} cardTitle="Repositories with leaks" loading={assessmentInQueuedState}>
            <DataCard.Counter
              count={assessment.total_repositories_with_results}
              total={assessment.distinct_repos_scanned}
            />
            <DataCard.Description>
              Repositories where secrets were detected out of all repositories scanned.
            </DataCard.Description>
          </DataCard>
        )}
      </div>
      <Table.Container>
        {noLeaks ? null : !assessmentInQueuedState ? (
          <>
            <h3 id={dataTableId} className="sr-only">
              Token leaks
            </h3>
            <DataTable
              aria-labelledby={dataTableId}
              data={data}
              // TODO get sorting working properly
              // initialSortColumn="unique_tokens_found_count"
              // initialSortDirection="DESC"
              columns={columns}
            />
            <Table.Pagination
              aria-label="Pagination for leaked secrets"
              totalCount={assessment.tokens.length}
              pageSize={pageSize}
              onChange={({pageIndex: newPageIndex}) => setPageIndex(newPageIndex)}
            />
          </>
        ) : (
          <Table.Skeleton aria-label="Token leaks scan in progress" columns={columns.map(x => ({header: x.header}))} />
        )}
      </Table.Container>
    </div>
  )
}

// TODO: Add unit tests
function UpsellBanner({
  cost,
  buttonVariant,
  successBanner,
  org,
  helpUrl,
  renderBanner,
  noLeaks,
  showPublicRepoOption,
  showEnableSecretProtectionButton = true,
}: {
  cost: Cost
  buttonVariant?: 'primary'
  successBanner: ReactNode
  org: string
  helpUrl: string
  renderBanner: (buttons: ReactNode) => ReactNode
  noLeaks: boolean
  showPublicRepoOption?: boolean
  showEnableSecretProtectionButton?: boolean
}) {
  const [currentModal, setCurrentModal] = useState<'publicRepos' | 'allRepos' | null>()
  const isPublicReposModal = currentModal === 'publicRepos'
  const isAllReposModal = currentModal === 'allRepos'
  const mutation = useMutation({
    mutationFn: async ({includePrivateRepos}: {includePrivateRepos: boolean}) => {
      const res = await reactFetchJSON(enableGhspPath(org), {
        method: 'PATCH',
        body: {includePrivateRepos},
      })
      if (!res.ok) {
        throw new Error('Failed to enable secret protection')
      }
    },
    onSettled: () => {
      setCurrentModal(null)
    },
  })

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const {data: configConflict = {hasConflict: false, failedCheck: false}, isLoading} = useQuery({
    queryKey: ['secret-scanning', org],
    queryFn: async () => {
      try {
        const res = await reactFetchJSON(hasConfigConflict(org), {method: 'GET'})
        if (!res.ok) {
          throw new Error('Failed to check for config conflicts')
        }
        const jsonResponse = await res.json()
        return {
          hasConflict: jsonResponse.has_repo_conflict,
          failedCheck: false,
        }
      } catch {
        return {hasConflict: true, failedCheck: true}
      }
    },
  })

  const enableAllButtonRef = useRef<HTMLButtonElement>(null)

  const EnableSecretProtectionButtons = (
    <>
      <Link
        href={`${helpUrl}/code-security/secret-scanning/introduction/about-secret-scanning`}
        onClick={() =>
          sendClickAnalyticsEvent({
            location: 'security-assessment-post-scan',
            category: noLeaks ? 'no-secrets-banner' : 'protect-repos-banner',
            action: 'learn-more',
            tag: 'link',
            group: 'expand',
          })
        }
      >
        Learn more
      </Link>
      <ActionMenu anchorRef={enableAllButtonRef}>
        <ActionMenu.Button ref={enableAllButtonRef} variant={buttonVariant}>
          Enable Secret Protection
        </ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList>
            {showPublicRepoOption && (
              <ActionList.Item
                loading={isLoading}
                disabled={isLoading}
                onSelect={() => {
                  setCurrentModal('publicRepos')
                  sendClickAnalyticsEvent({
                    location: 'security-assessment-post-scan',
                    category: noLeaks ? 'no-secrets-banner' : 'protect-repos-banner',
                    action: 'enable-for-public-repos',
                    tag: 'button',
                    group: 'exapnd',
                  })
                }}
              >
                For public repositories for free
              </ActionList.Item>
            )}
            <ActionList.Item
              onSelect={() => {
                setCurrentModal('allRepos')
                sendClickAnalyticsEvent({
                  location: 'security-assessment-post-scan',
                  category: noLeaks ? 'no-secrets-banner' : 'protect-repos-banner',
                  action: 'enable-for-all-repos',
                  tag: 'button',
                  group: 'expand',
                })
              }}
            >
              For all repositories
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {currentModal && (
        <Dialog
          className={clsx(styles.dialog)}
          title="Enable Secret Protection"
          data-analytics-visible='{"category":"enable-secret-protection-modal","action":"visible","group":"expand","location":"security-assessment-post-scan"}'
          onClose={() => {
            setCurrentModal(null)
          }}
          returnFocusRef={enableAllButtonRef}
          renderFooter={() => {
            return (
              <div className="d-flex flex-justify-end gap-2 p-3 border-top">
                <Button
                  as="a"
                  href={`/organizations/${org}/settings/security_products`}
                  onClick={() =>
                    sendClickAnalyticsEvent({
                      location: 'security-assessment-post-scan',
                      category: 'enable-secret-protection-modal',
                      action: 'configure-settings',
                      tag: 'button',
                      group: 'expand',
                    })
                  }
                >
                  Configure in settings
                </Button>
                <Button
                  variant="primary"
                  onClick={() => {
                    mutation.mutate({includePrivateRepos: isAllReposModal})
                    sendClickAnalyticsEvent({
                      location: 'security-assessment-post-scan',
                      category: 'enable-secret-protection-modal',
                      action: isAllReposModal
                        ? 'enable-secret-protection'
                        : 'enable-secret-protection-for-public-repos',
                      tag: 'button',
                      group: 'expand',
                    })
                  }}
                  loading={mutation.isPending}
                >
                  Enable Secret Protection
                </Button>
              </div>
            )
          }}
        >
          {isAllReposModal && (
            <>
              <p>
                This will enable <span className="text-bold">Secret Protection</span> with secret scanning alerts and
                push protection for all repositories.
              </p>
              <div className="mb-2 p-4 bgColor-inset rounded-2">
                <p>
                  <span className="f2">{cost.total}</span> / month
                </p>
                <span className="fgColor-muted">New additional cost for your organization</span>
                <hr />
                <p className="mb-0">{cost.increased_license_usage} Secret Protection license(s)</p>
                <span className="fgColor-muted">{cost.per_license} per active committer within the last 90 days</span>
              </div>
              <span className="fgColor-muted">
                You will be charged for additional committers in your next billing cycle.{' '}
                <Link
                  inline
                  href={`${helpUrl}/billing/managing-billing-for-your-products/managing-billing-for-github-advanced-security/about-billing-for-github-advanced-security`}
                >
                  Review billing information
                </Link>{' '}
                for more details.
              </span>
            </>
          )}
          {isPublicReposModal && <EnableAllPublicReposModalBody configConflict={configConflict} />}
        </Dialog>
      )}
    </>
  )

  return (
    <>
      {mutation.isError && (
        <Banner
          variant="critical"
          title="Error"
          description="Failed to enable Secret Protection. Please try again later."
        />
      )}
      {mutation.isSuccess
        ? successBanner
        : renderBanner(showEnableSecretProtectionButton && EnableSecretProtectionButtons)}
    </>
  )
}

function NoLeaksBanner({enableButtons, color}: {enableButtons: ReactNode; color: string}) {
  return (
    <div className="position-relative d-flex flex-justify-between p-4 mb-3 bgColor-muted border rounded-2">
      <div
        className="d-flex flex-column flex-justify-between"
        data-analytics-visible='{"category":"no-secrets-banner","action":"visible","group":"expand","location":"security-assessment-post-scan"}'
      >
        <h2 className="h3">Great work, there were no secret leaks found.</h2>
        <p className="mb-3 fgColor-muted f5">Stop leaks before they happen with Secret Protection.</p>
        <div className="d-flex flex-items-center gap-3">{enableButtons}</div>
      </div>
      <img
        className={clsx(styles.noLeaksImage, 'mt-3 mr-n4 mb-n4')}
        src={`/images/secret-scanning/risk-assessment/no_leaks_banner--${color}.png`}
        alt=""
      />
    </div>
  )
}

function NoLeaksSuccessBanner({color}: {color: string}) {
  const [isOpen, setIsOpen] = useState(true)
  return (
    isOpen && (
      <div className="position-relative overflow-hidden d-flex p-4 mb-3 bgColor-muted border rounded-2">
        <IconButton
          // Set focus to this element after the dialog closes when the user clicks the button to enable the GHSP
          autoFocus
          className="position-absolute top-0 right-0 mt-2 mr-2"
          variant="invisible"
          icon={XIcon}
          aria-label="Dismiss banner"
          onClick={() => setIsOpen(false)}
        />
        <div>
          <h2 className="h3 mb-2">Great work, there were no secret leaks found.</h2>
          <span className="fgColor-muted f5">Treat yourself — you did good today. ✨</span>
        </div>
        <img
          className={clsx(styles.noLeaksImage, 'position-absolute right-0 mt-3')}
          src={`/images/secret-scanning/risk-assessment/no_leaks_banner--${color}.png`}
          alt=""
        />
      </div>
    )
  )
}

function ContactAdministratorBanner() {
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  return (
    <Banner
      variant="warning"
      icon={<KeyIcon />}
      title="Protect your repositories from future leaks with Secret Protection"
      data-analytics-visible='{"category":"admin-contact-banner","action":"visible","group":"expand","location":"security-assessment-post-scan"}'
      description={
        <>
          Contact your enterprise license administrator to enable Secret Protection. They may be able to{' '}
          <Link
            inline
            href="https://github.com/enterprise/contact"
            onClick={() =>
              sendClickAnalyticsEvent({
                location: 'security-assessment-post-scan',
                category: 'admin-contact-banner',
                action: 'contact-github',
                tag: 'link',
                group: 'expand',
              })
            }
          >
            contact GitHub
          </Link>{' '}
          to obtain the right licenses.
        </>
      }
    />
  )
}

function AssessmentResultBanner({enableButtons}: {enableButtons: ReactNode}) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  return (
    <Banner
      variant="upsell"
      icon={<KeyIcon />}
      title="Protect your repositories from future leaks with Secret Protection"
      data-analytics-visible='{"category":"protect-repos-banner","action":"visible","group":"expand","location":"security-assessment-post-scan"}'
      description={
        <>
          Have questions?{' '}
          <Link
            inline
            href="https://github.com/security/advanced-security/secret-protection/contact-sales?utm_campaign=GHAS_secret_risk_assessment_contact_utmroutercampaign"
            onClick={() => {
              sendClickAnalyticsEvent({
                location: 'security-assessment-post-scan',
                category: 'results-banner',
                action: 'talk-to-someone',
                tag: 'link',
                group: 'expand',
              })
            }}
          >
            Talk to someone from GitHub
          </Link>{' '}
          to learn more about Secret Protection.
        </>
      }
      secondaryAction={enableButtons}
    />
  )
}

function ScanInProgressBanner() {
  const [isOpen, setIsOpen] = useState(true)
  const {sendClickAnalyticsEvent} = useClickAnalytics()
  return (
    isOpen && (
      <Banner
        title="Scan in progress, we'll email you when it's ready."
        data-analytics-visible='{"category":"scan-in-progress-banner","action":"visible","group":"expand","location":"security-assessment"}'
        description={
          <>
            Meanwhile,{' '}
            <Link inline href={`/resources/articles/security`}>
              explore resources
            </Link>{' '}
            like the{' '}
            <Link inline href={`/resources/whitepapers/secret-scanning-a-key-to-your-cybersecurity-strategy`}>
              secret leak expert guide
            </Link>
            .
          </>
        }
        icon={<InfoIcon />}
        variant="info"
        onDismiss={() => {
          setIsOpen(false)
          sendClickAnalyticsEvent({
            location: 'security-assessment',
            category: 'scan-in-progress-banner',
            action: 'dismiss',
            tag: 'icon',
            group: 'expand',
          })
        }}
      />
    )
  )
}

function InfoOverlay({helpUrl}: {helpUrl: string}) {
  const [isOpen, setIsOpen] = useState(false)
  return (
    <AnchoredOverlay
      className="p-4"
      side="outside-top"
      align="center"
      width="medium"
      open={isOpen}
      onOpen={() => setIsOpen(true)}
      onClose={() => setIsOpen(false)}
      // TODO: Need to override aria-labelledby to fix type error; reported to Primer
      renderAnchor={props => (
        <IconButton {...props} variant="invisible" icon={InfoIcon} aria-label="Info" aria-labelledby={undefined} />
      )}
    >
      <p className="text-bold">Secret categories</p>
      <p>
        GitHub scans for many types of secrets: generic secrets, like{' '}
        <Link
          inline
          href={`${helpUrl}/code-security/secret-scanning/copilot-secret-scanning/responsible-ai-generic-secrets`}
        >
          passwords detected with Copilot
        </Link>
        , and provider secrets, which come from third-party services through{' '}
        <Link inline href={`${helpUrl}/code-security/secret-scanning/introduction/about-secret-scanning-for-partners`}>
          GitHub&apos;s partner program
        </Link>{' '}
        — helping keep false positives low.
      </p>
    </AnchoredOverlay>
  )
}

function ProgressCardItem({
  label,
  labelColor,
  data,
}: {
  label: string
  labelColor: string
  data?: {count: number; total: number}
}) {
  return (
    <span className="d-inline-flex flex-items-center gap-1 f6">
      <DotFillIcon className={clsx(labelColor)} />
      <span>
        {/* Prevent divide by zero */}
        <span className="text-bold">{label}</span>{' '}
        <span>
          {data
            ? `${Math.round((100 * data.count) / (data.total || 1))}% (${data.count.toLocaleString()})`
            : 'Not scanned'}
        </span>
      </span>
    </span>
  )
}

function EnableAllPublicReposModalBody({
  configConflict,
}: {
  configConflict: {hasConflict: boolean; failedCheck: boolean}
}) {
  if (!configConflict.hasConflict) {
    return (
      <>
        <p>
          This will enable <span className="text-bold">Secret Protection</span> with secret scanning alerts and push
          protection for all public repositories. Advanced configuration options can be managed from your organization
          settings.
        </p>
      </>
    )
  }
  return (
    <>
      <Banner
        className="mb-3"
        title="Warning"
        hideTitle
        variant="warning"
        description={`This ${
          configConflict.failedCheck ? 'may ' : 'will '
        } detach existing configurations from public repositories. Features outside of Secret Protection will remain unchanged. To enable Secret Protection with configurations, go to Advanced Security settings.`}
      />
      This will enable secret scanning alerts with push protection for all public repositories.
    </>
  )
}
