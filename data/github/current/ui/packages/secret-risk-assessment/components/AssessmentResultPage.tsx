import {useId, useState} from 'react'
import {clsx} from 'clsx'
import DataCard from '@github-ui/data-card'
import {CheckIcon, KebabHorizontalIcon, SyncIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Link, RelativeTime, Spinner} from '@primer/react'
import {DataTable, Table} from '@primer/react/experimental'

import type {Assessment} from '../types'
import styles from './AssessmentResultPage.module.css'

export function AssessmentResultPage({assessment, helpUrl}: {assessment: Assessment; helpUrl: string}) {
  const [pageIndex, setPageIndex] = useState(0)
  const pageSize = 15
  const start = pageIndex * pageSize
  const end = start + pageSize
  const data = assessment.tokens.slice(start, end)

  const columns = [
    {
      header: 'Token type',
      field: 'name' as const,
    },
    {
      header: 'Secrets found',
      field: 'unique_tokens_found_count' as const,
      sortBy: true,
    },
  ]

  const dataTableId = useId()

  return (
    <div className="d-flex flex-column gap-3">
      <div>
        <div className="d-flex flex-justify-between">
          <h2 className="h3" data-hpc>
            Secrets in your organization
          </h2>
          <div className="d-flex flex-items-center gap-2">
            {assessment.is_complete ? (
              <span>
                <CheckIcon className="fgColor-success mr-2" />
                Scan completed <RelativeTime datetime={assessment.last_status_change} />
              </span>
            ) : (
              <>
                <Spinner size="small" />
                <span>
                  Scan {Math.round((100 * assessment.total_scans_completed) / assessment.total_scans_wanted)}% complete
                </span>
              </>
            )}
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton aria-label="More options" icon={KebabHorizontalIcon} />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay>
                <ActionList>
                  <ActionList.Item>
                    <div className={clsx(styles.rerunScanBtn)}>
                      <SyncIcon />
                      <span>Rerun scan</span>
                      {/* Empty element to space out the grid */}
                      <div />
                      <span className="fgColor-attention f6">
                        Next run available <RelativeTime datetime={assessment.next_request_available_at} />
                      </span>
                    </div>
                  </ActionList.Item>
                  {/* TODO: add "Download CSV" */}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </div>
        </div>
        <p className="fgColor-muted f5">This audits all repositories, regardless of enablement status.</p>
      </div>
      {/* TODO: Implement banner */}
      <div className="d-flex flex-justify-between gap-3">
        <DataCard cardTitle="Total secrets" loading={!assessment.is_complete}>
          <DataCard.Counter count={assessment.total_tokens_found} />
          <DataCard.Description>
            Secret leaks found across your organization repositories. Validate which secrets are still active with{' '}
            <Link
              href={`${helpUrl}/code-security/secret-scanning/introduction/about-secret-scanning#performing-validity-checks`}
              inline
            >
              validity checks
            </Link>
            .
          </DataCard.Description>
        </DataCard>
        <DataCard cardTitle="Public leaks" loading={!assessment.is_complete}>
          <DataCard.Counter count={assessment.total_tokens_found_in_public_repo} />
          <DataCard.Description>
            Distinct secrets which are visible publicly, across your public repositories.
          </DataCard.Description>
        </DataCard>
        <DataCard cardTitle="Preventable leaks" loading={!assessment.is_complete}>
          <DataCard.Counter count={assessment.total_tokens_found_push_protected_patterns} />
          <DataCard.Description>
            Secrets which could have been prevented.{' '}
            <Link href={`${helpUrl}/code-security/secret-scanning/introduction/about-push-protection`} inline>
              Push protection
            </Link>{' '}
            prevents developers from adding secrets remotely.
          </DataCard.Description>
        </DataCard>
      </div>
      <div className="d-flex flex-justify-between gap-3">
        {/* TODO: Implement progress cards */}
        <DataCard cardTitle="Secret locations" loading={!assessment.is_complete}>
          <DataCard.ProgressBar data={[{progress: 30, label: 'TODO'}]} />
          TODO
        </DataCard>
        <DataCard cardTitle="Secret categories" loading={!assessment.is_complete}>
          <DataCard.ProgressBar data={[{progress: 30, label: 'TODO'}]} />
          TODO
        </DataCard>
        {/* TODO: Implement repo counts */}
        <DataCard cardTitle="Repositories with leaks" loading={!assessment.is_complete}>
          <DataCard.Counter count={100} total={200} />
          <DataCard.Description>
            Repositories where secrets were detected, out of all repositories scanned.
          </DataCard.Description>
        </DataCard>
      </div>
      <Table.Container>
        {assessment.is_complete ? (
          <>
            <h3 id={dataTableId} className="sr-only">
              Token leaks
            </h3>
            <DataTable
              aria-labelledby={dataTableId}
              data={data}
              // TODO get sorting working properly
              initialSortColumn="unique_tokens_found_count"
              initialSortDirection="DESC"
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
