import {Box, Button, Details, useDetails} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type {LogGroup as ILogGroup, PipelineStageStatus, Stage} from '../../../../types'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {LogGroup} from './LogGroup'
import {useEffect, useMemo, useRef, type MouseEventHandler} from 'react'
import {StageIcon} from './StageIcon'
import {isInProgress, shouldAutoClose, shouldAutoOpen, wentBackwards} from './utils'
import {colors} from './colors'

interface Props {
  stage: Stage
}

function logGroupHasContent(logGroup: ILogGroup): boolean {
  // If there are any groupings, then we'll display the logGroup.name, so thus it has content.
  // If it's not grouped, then we check if there are any logGroup.logs.
  return logGroup.ui_group_logs || logGroup.logs.length > 0
}

export function Stage({stage}: Props) {
  const {name, status, log_groups: logGroups} = stage
  const {getDetailsProps, open: isOpen, setOpen} = useDetails({defaultOpen: isInProgress(status)})
  const hasBeenClickedRef = useRef(false)
  const prevStageRef = useRef<PipelineStageStatus | undefined>()

  const hasAnyLogContent = useMemo(() => logGroups.some(logGroupHasContent), [logGroups])
  const isEmpty = !hasAnyLogContent

  useEffect(() => {
    // We do not want to auto open/close an accordion if the user has already interacted with it. Only auto
    // open/close when the user has not taken action.
    if (hasBeenClickedRef.current) return

    const prev = prevStageRef.current
    const curr = status

    // This hook is always called twice, with the second time having the order
    // _reversed_, so we always want to enforce it going forward. It is most likely
    // called twice due to the needed dependency on `setOpen`.
    if (wentBackwards(prev, curr)) return
    if (prev === curr) return

    if (shouldAutoOpen(prev, curr)) setOpen(true)
    if (shouldAutoClose(prev, curr)) setOpen(false)

    prevStageRef.current = curr
  }, [status, setOpen, isOpen])

  const handleClick: MouseEventHandler = e => {
    if (isEmpty) {
      e.preventDefault()
      return
    } else {
      // Do not track expansion when it's empty
      hasBeenClickedRef.current = true
    }
  }

  return (
    <Details {...getDetailsProps()}>
      <Button
        alignContent="start"
        as="summary"
        onClick={handleClick}
        sx={{
          backgroundColor: isOpen ? `${colors.control.bg.active} !important` : 'transparent',
          '&:active': {
            backgroundColor: isEmpty ? 'transparent !important' : `${colors.control.bg.active} !important`,
          },
          '&:hover': {
            backgroundColor: isEmpty
              ? 'transparent !important'
              : isOpen
                ? `${colors.control.bg.active} !important`
                : `${colors.actionListItem.default.hoverBg} !important`,
          },
          border: 'solid 1px transparent !important',
          boxShadow: 'none',
          color: isOpen ? colors.fg.default : colors.fg.muted,
          cursor: isEmpty ? 'default' : 'pointer',
          fontWeight: 'normal',
          p: '8px',
        }}
      >
        <Box sx={{alignItems: 'center', display: 'flex', gap: '8px'}}>
          <Octicon
            icon={isOpen ? ChevronDownIcon : ChevronRightIcon}
            sx={{visibility: isEmpty ? 'hidden' : 'inherit'}}
          />
          <StageIcon status={status} />
          <span>{name}</span>
        </Box>
      </Button>

      <Box sx={{my: '8px', px: '16px'}}>
        {logGroups.map(logGroup => (
          <LogGroup key={logGroup.name} logGroup={logGroup} />
        ))}
      </Box>
    </Details>
  )
}
