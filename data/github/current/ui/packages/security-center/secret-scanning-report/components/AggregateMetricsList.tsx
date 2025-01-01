import DataCard from '@github-ui/data-card'
import type {Icon} from '@primer/octicons-react'
import {CounterLabel, Spinner, Stack, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Blankslate} from '@primer/react/experimental'

import {appendQuery} from '../../common/utils/url'
import {
  type AggregateCount,
  AggregateCountType,
  type BypassReasonCount,
  type RepositoryCount,
  type TokenTypeCount,
} from '../types/push-protection-metrics'
import styles from './AggregateMetricsList.module.css'

const MAX_TABLE_SIZE = 4

export interface AggregateMetricsListProps {
  icon?: Icon
  title: string
  // eslint-disable-next-line @typescript-eslint/naming-convention
  'data-testid'?: string
  aggregateCounts: AggregateCount[]
  seeAllButton?: JSX.Element
  baseIndexLink?: string
  loading?: boolean
}

export function AggregateMetricsList({
  title,
  aggregateCounts,
  icon,
  'data-testid': testId,
  seeAllButton,
  baseIndexLink,
  loading,
}: AggregateMetricsListProps): JSX.Element {
  return (
    <DataCard data-testid={testId} className={styles.DataCard}>
      <div className={styles.Heading}>{ListHeading(title, icon)}</div>
      {MetricList(aggregateCounts, seeAllButton, baseIndexLink, loading)}
    </DataCard>
  )
}

function ListHeading(title: string, icon?: Icon): JSX.Element {
  if (icon) {
    return (
      <Stack direction="horizontal" align="center" gap="condensed">
        <Octicon icon={icon} size={16} />
        <Text weight="semibold">{title}</Text>
      </Stack>
    )
  }

  return <span className={styles.Text}>{title}</span>
}

function MetricList(
  aggregateCounts: AggregateCount[],
  seeAllButton?: JSX.Element,
  baseIndexLink?: string,
  loading?: boolean,
): JSX.Element {
  if (loading) {
    return (
      <div data-testid="metrics-list-loading-skeleton" className={styles.Box}>
        <Spinner />
      </div>
    )
  }

  if (aggregateCounts.length) {
    return (
      <ul className={styles.List}>
        {aggregateCounts.map(count => AggregateCountListItem(count, baseIndexLink))}
        {aggregateCounts.length >= MAX_TABLE_SIZE && seeAllButton}
      </ul>
    )
  }

  return emptyListBlankSlate()
}

function emptyListBlankSlate(): JSX.Element {
  return (
    <div data-testid="empty-metrics-list-blankslate" className={styles.Box_1}>
      <Blankslate>
        <Blankslate.Heading>
          <span className={styles.Text_1}>No data</span>
        </Blankslate.Heading>
        <Blankslate.Description>Try modifying your filters or clear your search.</Blankslate.Description>
      </Blankslate>
    </div>
  )
}

export function AggregateCountListItem(count: AggregateCount, baseIndexLink?: string): JSX.Element | null {
  switch (count.type) {
    case AggregateCountType.TokenType:
      return baseIndexLink ? TokenTypeLinkItem(count, baseIndexLink) : TokenTypeListItem(count)
    case AggregateCountType.Repository:
      return baseIndexLink ? RepoLinkItem(count, baseIndexLink) : RepoListItem(count)
    case AggregateCountType.BypassReason:
      return BypassReasonListItem(count)
    default:
      return null
  }
}

function TokenTypeListItem(count: TokenTypeCount): JSX.Element {
  let tokenTypeDisplayName = count.name

  if (count.hasMetadata) {
    if (count.isCustomPattern) {
      tokenTypeDisplayName += ' (custom pattern)'
    }

    return (
      <li className={styles.ListItem} key={tokenTypeDisplayName}>
        <p>{tokenTypeDisplayName}</p>
        <div>
          <CounterLabel>{count.count}</CounterLabel>
        </div>
      </li>
    )
  } else {
    return (
      <li className={styles.ListItem} key={tokenTypeDisplayName}>
        <p>{tokenTypeDisplayName}</p>
        <div>
          <CounterLabel>{count.count}</CounterLabel>
        </div>
      </li>
    )
  }
}

function TokenTypeLinkItem(count: TokenTypeCount, baseIndexLink: string): JSX.Element {
  let tokenTypeDisplayName = count.name

  if (count.hasMetadata) {
    if (count.isCustomPattern) {
      tokenTypeDisplayName += ' (custom pattern)'
    }

    return (
      <li className={styles.ListItem} key={tokenTypeDisplayName}>
        <a href={appendQuery({baseUrl: baseIndexLink, query: `secret-type:${count.slug}`})}>{tokenTypeDisplayName}</a>
        <div>
          <CounterLabel>{count.count}</CounterLabel>
        </div>
      </li>
    )
  } else {
    return (
      <li className={styles.ListItem} key={tokenTypeDisplayName}>
        <p>{tokenTypeDisplayName}</p>
        <div>
          <CounterLabel>{count.count}</CounterLabel>
        </div>
      </li>
    )
  }
}

function RepoListItem(count: RepositoryCount): JSX.Element {
  return (
    <li className={styles.ListItem} key={count.name}>
      <p>{count.name}</p>
      <div>
        <CounterLabel>{count.count}</CounterLabel>
      </div>
    </li>
  )
}

function RepoLinkItem(count: RepositoryCount, baseIndexLink: string): JSX.Element {
  return (
    <li className={styles.ListItem} key={count.name}>
      <a href={appendQuery({baseUrl: baseIndexLink, query: `repo:${count.name}`})}>{count.name}</a>
      <div>
        <CounterLabel>{count.count}</CounterLabel>
      </div>
    </li>
  )
}

function BypassReasonListItem(count: BypassReasonCount): JSX.Element {
  let counterLabelText = String(count.count)
  if (count.count) {
    counterLabelText = `${count.count} (${count.percent}%)`
  }

  return (
    <li className={styles.ListItem} key={count.name}>
      <p>{count.name}</p>
      <div>
        <CounterLabel>{counterLabelText}</CounterLabel>
      </div>
    </li>
  )
}
