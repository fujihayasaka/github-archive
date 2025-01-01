import {GitHubAvatar} from '@github-ui/github-avatar'
import {
  AlertIcon,
  CheckIcon,
  ClockIcon,
  DotFillIcon,
  IssueReopenedIcon,
  SkipIcon,
  SquareFillIcon,
  StopIcon,
  XIcon,
} from '@primer/octicons-react'
import {Box, Link, Text, Tooltip} from '@primer/react'

import type {CheckRun} from '../index'

export default function CheckRunItem({checkRun}: {checkRun: CheckRun}) {
  const iconJsx = getOcticonFromIconString(checkRun.icon)
  const inProgress = checkRun.state === 'in_progress'
  return (
    <Box
      data-testid="check-run-item"
      as="li"
      sx={{
        display: 'flex',
        borderBottomWidth: '1px',
        borderBottomStyle: 'solid',
        borderBottomColor: 'border.default',
        backgroundColor: 'canvas.subtle',
        py: 2,
        pr: 3,
        pl: '12px',
        alignItems: 'center',
      }}
    >
      <Box sx={{alignSelf: 'center', display: 'flex'}}>
        {inProgress ? getInProgressSpinner() : <>{iconJsx}</>}
        <Tooltip text={checkRun.avatarDescription} direction="e">
          <Link href={checkRun.avatarUrl} sx={{mr: 2}} aria-label="Avatar">
            <GitHubAvatar square src={checkRun.avatarLogo} sx={{backgroundColor: checkRun.avatarBackgroundColor}} />
          </Link>
        </Tooltip>
      </Box>
      <Text sx={{fontSize: '13px', color: 'fg.muted'}}>
        <Text sx={{fontWeight: 'bold', color: 'fg.default', mr: '2px'}}>{checkRun.name} </Text>
        {checkRun.pending ? (
          <Text sx={{fontStyle: 'italic'}}>{checkRun.additionalContext}</Text>
        ) : (
          checkRun.additionalContext
        )}
        {checkRun.description && (
          <span>
            {' '}
            - {checkRun.pending ? <Text sx={{fontStyle: 'italic'}}>{checkRun.description}</Text> : checkRun.description}
          </span>
        )}
      </Text>

      <Link href={checkRun.targetUrl} sx={{pl: '12px', fontSize: '13px', marginLeft: 'auto'}}>
        Details
      </Link>
    </Box>
  )
}

function getOcticonFromIconString(icon: string) {
  switch (icon) {
    case 'check':
      return <CheckIcon className={'fgColor-success my-0 mx-2 flex-self-center'} />
    case 'dot-fill':
      return <DotFillIcon className={'fgColor-attention my-0 mx-2 flex-self-center'} />
    case 'stop':
      return <StopIcon className={'fgColor-muted my-0 mx-2 flex-self-center'} />
    case 'issue-reopened':
      return <IssueReopenedIcon className={'fgColor-muted my-0 mx-2 flex-self-center'} />
    case 'clock':
      return <ClockIcon className={'fgColor-attention my-0 mx-2 flex-self-center'} />
    case 'square-fill':
      return <SquareFillIcon className={'fgColor-default my-0 mx-2 flex-self-center'} />
    case 'skip':
      return <SkipIcon className={'fgColor-muted my-0 mx-2 flex-self-center'} />
    case 'alert':
      return <AlertIcon className={'fgColor-danger my-0 mx-2 flex-self-center'} />
    default:
      return <XIcon className={'fgColor-danger my-0 mx-2 flex-self-center'} />
  }
}

function getInProgressSpinner() {
  return (
    <Box sx={{height: '16px', width: '16px', minWidth: '16px', alignSelf: 'center', mx: '7px'}}>
      <svg fill="none" viewBox="0 0 16 16" className="anim-rotate" aria-hidden="true" role="img">
        <path opacity=".5" d="M8 15A7 7 0 108 1a7 7 0 000 14v0z" stroke="#dbab0a" strokeWidth="2" />
        <path d="M15 8a7 7 0 01-7 7" stroke="#dbab0a" strokeWidth="2" />
        <path d="M8 12a4 4 0 100-8 4 4 0 000 8z" fill="#dbab0a" />
      </svg>
    </Box>
  )
}
