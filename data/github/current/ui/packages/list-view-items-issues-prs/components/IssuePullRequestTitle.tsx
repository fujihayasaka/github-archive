import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'
import type React from 'react'
import {useCallback, useMemo, type ComponentProps, type ForwardedRef} from 'react'
import {graphql, useFragment, type PreloadedQuery} from 'react-relay'

import {Label} from './labels/Label'
import type {IssuePullRequestTitle$key} from './__generated__/IssuePullRequestTitle.graphql'
import {issueHovercardPath, issueLinkedPullRequestHovercardPath} from '@github-ui/paths'
import {IssueItemSubIssuesSummary} from './IssueItemSubIssuesSummary'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'

import styles from './IssuePullRequestTitle.module.css'
import {clsx} from 'clsx'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

const titleFragment = graphql`
  fragment IssuePullRequestTitle on IssueOrPullRequest
  @argumentDefinitions(labelPageSize: {type: "Int!", defaultValue: 10}) {
    __typename
    ... on Issue {
      id
      number
      labels(first: $labelPageSize, orderBy: {field: NAME, direction: ASC}) {
        nodes {
          ...Label
          name
          id
        }
      }
    }
    ... on PullRequest {
      number
      labels(first: $labelPageSize, orderBy: {field: NAME, direction: ASC}) {
        nodes {
          ...Label
          name
          id
        }
      }
    }
  }
`

type IssuePullRequestTitleProps = {
  dataKey: IssuePullRequestTitle$key
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
  repositoryOwner: string
  repositoryName: string
  ref?: ForwardedRef<HTMLAnchorElement>
  href?: string
  target?: string
  onClick?: React.MouseEventHandler<HTMLElement>
  value: ComponentProps<typeof ListItemTitle>['value']
  leadingBadge?: ComponentProps<typeof ListItemTitle>['leadingBadge']
  /**
   * Href getter for the label badge links
   * @param name - name of the label
   * @returns URL to the label
   */
  getLabelHref: (name: string) => string
  /**
   * Href getter for the sub-issues progress badge links
   * @param owner - owner of the issue's repository
   * @param repo - name of the issue's repository
   * @param number - number of the issue
   * @returns URL with query for the sub-issues of the issue
   */
  getSubIssuesHref?: (owner: string, repo: string, number: number) => string
  headerClassName?: string
}

export function IssuePullRequestTitle({
  dataKey,
  metadataRef,
  ref,
  href,
  target,
  onClick: externalOnClick,
  value,
  leadingBadge,
  getLabelHref,
  getSubIssuesHref,
  headerClassName,
  repositoryOwner,
  repositoryName,
}: IssuePullRequestTitleProps) {
  const data = useFragment(titleFragment, dataKey)
  const {sub_issues} = useFeatureFlags()

  const {number, labels} =
    data.__typename === 'PullRequest' || data.__typename === 'Issue' ? data : {number: undefined, labels: undefined}

  const hoverCardProps = useMemo(() => {
    return number
      ? {
          'data-hovercard-url': createHovercardUrl(data.__typename, repositoryOwner, repositoryName, number),
          sx: {
            color: 'fg.default',
            ':hover': {
              color: 'accent.fg',
              textDecoration: 'none',
            },
          },
        }
      : {}
  }, [data.__typename, number, repositoryName, repositoryOwner])

  const onClick = useCallback(
    (event: React.MouseEvent<HTMLElement>) => {
      // shortcircuit to default link behaviors if using middle click or modifiers
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.button === 1 || event.shiftKey || event.ctrlKey || event.metaKey) return
      externalOnClick?.(event)
    },
    [externalOnClick],
  )

  const trailingLabels = (labels?.nodes || []).flatMap(a => a || [])
  const trailingBadges = [
    ...trailingLabels.map(label => (
      <ListItemTrailingBadge key={label.id} title={label.name}>
        <Label label={label} getLabelHref={getLabelHref} fontWeight={500} />
      </ListItemTrailingBadge>
    )),
  ]

  if (data.__typename === 'Issue' && sub_issues) {
    const subIssuesSummary = (
      <IssueItemSubIssuesSummary
        metadataRef={metadataRef}
        issueId={data.id}
        link={number && getSubIssuesHref ? getSubIssuesHref(repositoryOwner, repositoryName, number) : ''}
        key="sub-issues-summary"
      />
    )
    if (subIssuesSummary) trailingBadges.unshift(subIssuesSummary)
  }

  return (
    <ListItemTitle
      value={value}
      anchorRef={ref}
      href={href}
      target={target}
      onClick={onClick}
      leadingBadge={leadingBadge}
      trailingBadges={trailingBadges}
      linkProps={hoverCardProps}
      headingClassName={clsx(headerClassName, styles.ListItemTitle_0)}
    />
  )
}

function createHovercardUrl(typeName: 'Issue' | 'PullRequest' | '%other', owner: string, repo: string, number: number) {
  switch (typeName) {
    case 'PullRequest':
      return issueLinkedPullRequestHovercardPath({
        owner,
        repo,
        pullRequestNumber: number,
      })
    case 'Issue':
      return issueHovercardPath({
        owner,
        repo,
        issueNumber: number,
      })
    default:
      return ''
  }
}
