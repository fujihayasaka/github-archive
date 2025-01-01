import {Box, Link, Token} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import {issueHovercardPath} from '@github-ui/paths'
import type {HeaderParentTitle$data, HeaderParentTitle$key} from './__generated__/HeaderParentTitle.graphql'

import type {OptionConfig} from '../OptionConfig'
import type {SubIssueSidePanelItem} from '@github-ui/sub-issues/sub-issue-types'
import type React from 'react'
import {issueUrl} from '../../utils/urls'
import {useIssueState} from '@github-ui/use-issue-state'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'

type HeaderParentTitleProps = {
  parentKey?: HeaderParentTitle$key
  small?: boolean
} & SharedProps

type HeaderParentTitleInternalProps = {
  parent: NonNullable<HeaderParentTitle$data['parent']>
  small?: boolean
} & SharedProps

type SharedProps = {
  optionConfig?: OptionConfig
}

const MAX_WIDTH = 500

/** The internal component that renders the parent title itself after all data fetching has occurred */
export const HeaderParentTitle = ({parentKey, optionConfig, small = false}: HeaderParentTitleProps) => {
  const data = useFragment(
    graphql`
      fragment HeaderParentTitle on Issue {
        parent {
          id
          number
          repository {
            name
            owner {
              login
            }
          }
          state
          stateReason(enableDuplicate: true)
          title
          titleHTML
          url
        }
      }
    `,
    parentKey,
  )

  if (!data) {
    return null
  }
  const {parent} = data

  // The data from this fragment is not _all_ available yet, as it's requested in the secondary query, however,
  // AddSubIssueButtonGroup requests parent.id which is available in the primary query. useFragment, seemingly
  // merges this partial data and we are left with a parent object that is not empty, but also not fully populated.
  // See: https://github.com/github/github/issues/333236
  if (!parent?.repository) {
    return null
  }

  return <HeaderParentTitleInternal parent={parent} optionConfig={optionConfig} small={small} />
}

const HeaderParentTitleInternal = ({parent, optionConfig, small = false}: HeaderParentTitleInternalProps) => {
  const repo = parent.repository.name
  const owner = parent.repository.owner.login

  const {sourceIcon} = useIssueState({
    state: parent.state,
    stateReason: parent.stateReason,
  })
  const {icon: IconComponent, color, label} = sourceIcon('Issue')

  if (!IconComponent) return null

  const handleOpen = (e: React.MouseEvent | React.KeyboardEvent) => {
    // If in the side panel and the parent issue is the same as the current issue, just close the side panel
    if (optionConfig?.onParentIssueActivate) {
      const itemIdentifier = {number: parent.number, repo, owner, type: 'Issue'} as const
      const closedSidePanel = optionConfig.onParentIssueActivate(e, itemIdentifier)
      if (closedSidePanel) return
    }

    // Else if in the side panel and the parent issue is different than the current issue,
    // open the parent issue in the side panel
    if (optionConfig?.insideSidePanel && optionConfig?.onSubIssueClick) {
      const {id, number, state, title, url} = parent
      const subIssueItem: SubIssueSidePanelItem = {
        id: parseInt(id, 10),
        number,
        owner,
        repo,
        state,
        title,
        url,
      }
      e.preventDefault()
      optionConfig.onSubIssueClick(subIssueItem)
    }
    if (optionConfig?.navigate) {
      // If not in the side panel, navigate to the parent issue
      e.preventDefault()
      optionConfig?.navigate?.(issueUrl({number: parent.number, repo, owner}))
    }
  }

  const handleClick = (e: React.MouseEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return
    handleOpen(e)
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (e.key !== 'Enter' || e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return
    handleOpen(e)
  }

  const title = (parent.titleHTML || parent.title) as SafeHTMLString

  const tokenContent = (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        maxWidth: MAX_WIDTH,
      }}
    >
      <Box as="span" sx={{color}}>
        <IconComponent size={14} title={label} />
      </Box>
      <span style={{marginLeft: '4px'}}>Parent:</span>
      <Link
        aria-label={`Parent issue: ${parent.title}`}
        inline
        muted
        hoverColor="fg.muted"
        href={parent.url}
        onClick={handleClick}
        onKeyDown={handleKeyDown}
        data-hovercard-url={issueHovercardPath({
          owner,
          repo,
          issueNumber: parent.number,
        })}
        sx={{
          '&:not(:hover)': {textDecoration: 'none !important'},
          marginLeft: 1,
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
        }}
      >
        {small ? `#${parent.number}` : <SafeHTMLText html={title} className="markdown-title" />}
      </Link>
    </Box>
  )

  if (small) return tokenContent

  return (
    <>
      <Box sx={{width: 1, height: 18, borderRight: '1px solid', borderColor: 'border.default'}} />
      <Box sx={{maxWidth: `min(${MAX_WIDTH}px, 100%)`}}>
        <Token
          text={tokenContent}
          size={'xlarge'}
          sx={{
            px: 'calc(var(--control-small-paddingInline-normal) - 1px)', // account for the 1px border here
            backgroundColor: 'canvas.default',
            fontWeight: '400',
            fontSize: 0,
            gap: 1,
          }}
        />
      </Box>
    </>
  )
}
