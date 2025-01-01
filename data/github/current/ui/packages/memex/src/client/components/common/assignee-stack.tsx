import {GitHubAvatar} from '@github-ui/github-avatar'
import {usePortalTooltip} from '@github-ui/portal-tooltip/use-portal-tooltip'
import {type TestIdProps, testIdProps} from '@github-ui/test-id-props'
import {AvatarStack, type BetterSystemStyleObject, Box, Text} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useRef} from 'react'

import type {IAssignee, User} from '../../api/common-contracts'
import {joinOxford} from '../../helpers/join-oxford'
import {useSearch} from '../filter-bar/search-context'

type Props = TestIdProps & {
  assignees?: Array<User>
  alignRight?: boolean
  sx?: BetterSystemStyleObject
  wrapperSx?: BetterSystemStyleObject
  avatarProps?: Partial<React.HTMLAttributes<HTMLElement>>
}

const AVATAR_STACK_STYLE: BetterSystemStyleObject = {zIndex: 0}

type ClickableAvatarProps = {
  assignee: IAssignee
  sx?: BetterSystemStyleObject
} & Partial<React.HTMLAttributes<HTMLElement>>

const clickableAvatarItemWrapperStyle: BetterSystemStyleObject = {
  cursor: 'pointer',
  borderRadius: '50%',
  flexShrink: 0,
  '&:focus-visible': {
    outline: theme => `2px solid ${theme.colors.fg.danger}`,
    outlineOffset: 0,
  },
  '.pc-AvatarItem': {
    display: 'block',
  },
}

// Note that extra props are passed in by the <AvatarStack> component parent
const ClickableAvatar = ({assignee, onFocus, className, ...props}: ClickableAvatarProps) => {
  const {toggleFilter} = useSearch()

  const toggleFilterOnClick = useCallback(
    (event: React.MouseEvent<HTMLImageElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (!event.shiftKey && !event.metaKey) {
        // If the shift or meta key is held, we are assuming the user wants to
        // select multiple cards, in which case filtering would break
        // expectation and cause them to lose their selections.
        toggleFilter('assignee', assignee.login)
      }
    },
    [toggleFilter, assignee.login],
  )
  const toggleFilterOnEnter = useCallback(
    (event: React.KeyboardEvent<HTMLImageElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.key === 'Enter') {
        toggleFilter('assignee', assignee.login)
      }
    },
    [toggleFilter, assignee.login],
  )

  const avatar = useRef<HTMLImageElement>(null)
  const [contentProps, tooltip] = usePortalTooltip({
    contentRef: avatar,
    'aria-label': assignee.login,
  })

  return (
    <Text
      sx={{...clickableAvatarItemWrapperStyle, ...props.sx}}
      onClick={toggleFilterOnClick}
      onFocus={onFocus}
      onKeyDown={toggleFilterOnEnter}
      tabIndex={0}
      className={clsx(className, 'pc-AvatarItem memex-AvatarItem')}
      role="button"
      aria-label={assignee.login}
      {...testIdProps('AvatarItemFilterButton')}
    >
      <GitHubAvatar
        {...props}
        ref={avatar}
        loading="lazy"
        alt={assignee.login}
        src={assignee.avatarUrl}
        {...contentProps}
      />
      {tooltip}
    </Text>
  )
}

function getAssigneesText(assignees: Array<User>, opts = {reverse: false}) {
  if (assignees.length === 0) return 'none'
  const logins = assignees.map(a => a.login)
  return joinOxford(opts.reverse ? logins.reverse() : logins)
}

const assigneeStackStyles: BetterSystemStyleObject = {all: 'unset', m: 0, p: 0}

const avatarStackWrapperStyle: BetterSystemStyleObject = {
  '.pc-AvatarStackBody:focus-within': {
    width: 'auto',
  },
  '.pc-AvatarStackBody:focus-within .pc-AvatarItem:first-child': {
    mr: '0px !important',
  },
  '.pc-AvatarStackBody:focus-within .pc-AvatarItem': {
    mr: '4px !important',
    ml: '0px !important',
    opacity: 1,
  },
}

export const AssigneeStack = ({assignees, alignRight = false, sx, avatarProps, wrapperSx, ...props}: Props) => {
  if (assignees === undefined || assignees.length === 0) {
    return null
  }

  return (
    <Box
      as="figure"
      {...props}
      sx={{
        ...wrapperSx,
        ...avatarStackWrapperStyle,
        ...assigneeStackStyles,
      }}
    >
      <figcaption className="sr-only">Assignees: {getAssigneesText(assignees, {reverse: alignRight})}</figcaption>
      <AvatarStack alignRight={alignRight} sx={{...AVATAR_STACK_STYLE, ...sx}}>
        {assignees.map(assignee => (
          <ClickableAvatar key={assignee.id} assignee={assignee} {...avatarProps} />
        ))}
      </AvatarStack>
    </Box>
  )
}
