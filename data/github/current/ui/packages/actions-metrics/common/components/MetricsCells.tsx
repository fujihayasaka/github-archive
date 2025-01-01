import {KebabHorizontalIcon, RepoIcon, RepoLockedIcon} from '@primer/octicons-react'
import type {Repository} from '../models/models'
import {ActionList, ActionMenu, IconButton, Link, Truncate, VisuallyHidden, LabelGroup, Label} from '@primer/react'
import {Utils} from '../utils/utils'
import {RequestType} from '../models/enums'

import {LABELS} from '../resources/labels'

interface MetricsCellProps {
  children: React.ReactNode
  tooltip?: string
}
export function MetricsCell(props: MetricsCellProps) {
  return (
    <Truncate inline title={props.tooltip || ''} sx={{maxWidth: '100%'}}>
      <>{props.children}</>
    </Truncate>
  )
}

export function RepositoryCell(repository?: Repository, linkToMetrics?: boolean, requestType?: RequestType) {
  if (!repository) {
    return BlankCell()
  }

  const icon = repository.public ? (
    <RepoIcon size={16} className="mr-2" />
  ) : (
    <RepoLockedIcon size={16} className="mr-2" />
  )

  let url = repository.url

  if (linkToMetrics && requestType) {
    if (requestType === RequestType.Performance) {
      url += `/actions/metrics/performance`
    } else if (requestType === RequestType.Usage) {
      url += `/actions/metrics/usage`
    }
  }

  return (
    <MetricsCell tooltip={repository.name}>
      {icon} <LinkCell href={url}>{repository.name}</LinkCell>
    </MetricsCell>
  )
}

export function WorkflowCell(workflow?: string, repository?: Repository) {
  if (workflow && repository) {
    const href = `${repository.url}/actions/workflows/${workflow}`
    const workflowFileName = Utils.getFileNameFromPath(workflow)
    return (
      <MetricsCell tooltip={workflowFileName || ''}>
        <LinkCell href={href}>{workflowFileName}</LinkCell>
      </MetricsCell>
    )
  }

  if (workflow) {
    const workflowFileName = workflow.split('/').pop()
    return <MetricsCell tooltip={workflowFileName || ''}>{workflowFileName}</MetricsCell>
  }

  return BlankCell()
}

export function NumberCell(num?: number, approximate?: boolean) {
  let numberToShow = ''

  if (num !== undefined) {
    let approximateNumber = num

    if (approximate) {
      approximateNumber = Math.floor(approximateNumber / 1000) * 1000 // round down to nearest thousand
    }

    numberToShow = approximateNumber?.toLocaleString() ?? ''
  }

  if (numberToShow && approximate) {
    numberToShow += '+'
  }

  return <MetricsCell tooltip={numberToShow}>{numberToShow}</MetricsCell>
}

export function PercentCell(num?: number) {
  let numberToShow = ''

  if (num !== undefined) {
    numberToShow = Utils.getPercentage(num)
  }

  return <MetricsCell>{numberToShow}</MetricsCell>
}

export function DurationCell(num?: number) {
  // number => xd xh xm xs
  let textToShow = ''

  if (num !== undefined) {
    textToShow = Utils.getDuration(num)
  }

  return <MetricsCell>{textToShow}</MetricsCell>
}

export function TextCell(str?: string) {
  return <MetricsCell tooltip={str ?? ''}>{str ?? ''}</MetricsCell>
}

export function LabelCell(labels?: string) {
  if (!labels) {
    return BlankCell()
  }
  return (
    <LabelGroup>
      {labels
        ?.split(',')
        .map(value => value.trim())
        .map(label => (
          <Label key={label}>
            <Truncate inline title={label} sx={{maxWidth: '150px'}}>
              {label}
            </Truncate>
          </Label>
        ))}
    </LabelGroup>
  )
}

interface LinkCellProps {
  href: string
  ariaLabel?: string
  children: React.ReactNode
}
function LinkCell(props: LinkCellProps) {
  return (
    <Link href={props.href} aria-label={props.ariaLabel}>
      {props.children}
    </Link>
  )
}

export function JobsLinkCell(href: string, onClick: () => void, num?: number, approximate?: boolean) {
  return (
    <Link
      href={href}
      onClick={event => {
        event.preventDefault()
        onClick()
      }}
    >
      {NumberCell(num, approximate)}
    </Link>
  )
}

export function HiddenHeader(title: string) {
  return <VisuallyHidden>{title}</VisuallyHidden>
}

function BlankCell() {
  return <></>
}

export function ActionMenuCell(currentMetricsType: RequestType, href: string) {
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton
          aria-label={LABELS.rowActions}
          title={LABELS.rowActions}
          icon={KebabHorizontalIcon}
          variant="invisible"
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList>
          <ActionList.LinkItem href={href}>
            {currentMetricsType === RequestType.Performance ? LABELS.viewUsage : LABELS.viewPerformance}
          </ActionList.LinkItem>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
