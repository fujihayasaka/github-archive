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
import {Link, Tooltip} from '@primer/react'

import type {CheckRun} from '../index'

import styles from './CheckRunItem.module.css'

export default function CheckRunItem({checkRun}: {checkRun: CheckRun}) {
  const iconJsx = getOcticonFromIconString(checkRun.icon)
  const inProgress = checkRun.state === 'in_progress'
  return (
    <li data-testid="check-run-item" className={styles.Box}>
      <div className={styles.Box_1}>
        {inProgress ? getInProgressSpinner() : <>{iconJsx}</>}
        <Tooltip text={checkRun.avatarDescription} direction="e">
          <Link href={checkRun.avatarUrl} aria-label="Avatar" className={styles.Link}>
            <GitHubAvatar square src={checkRun.avatarLogo} sx={{backgroundColor: checkRun.avatarBackgroundColor}} />
          </Link>
        </Tooltip>
      </div>
      <span className={styles.Text}>
        <span className={styles.Text_1}>{checkRun.name} </span>
        {checkRun.pending ? (
          <span className={styles.Text_2}>{checkRun.additionalContext}</span>
        ) : (
          checkRun.additionalContext
        )}
        {checkRun.description && (
          <span>
            {' '}
            - {checkRun.pending ? <span className={styles.Text_2}>{checkRun.description}</span> : checkRun.description}
          </span>
        )}
      </span>
      <Link href={checkRun.targetUrl} className={styles.Link_1}>
        Details
      </Link>
    </li>
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
    <div className={styles.Box_2}>
      <svg fill="none" viewBox="0 0 16 16" className="anim-rotate" aria-hidden="true" role="img">
        <path opacity=".5" d="M8 15A7 7 0 108 1a7 7 0 000 14v0z" stroke="#dbab0a" strokeWidth="2" />
        <path d="M15 8a7 7 0 01-7 7" stroke="#dbab0a" strokeWidth="2" />
        <path d="M8 12a4 4 0 100-8 4 4 0 000 8z" fill="#dbab0a" />
      </svg>
    </div>
  )
}
