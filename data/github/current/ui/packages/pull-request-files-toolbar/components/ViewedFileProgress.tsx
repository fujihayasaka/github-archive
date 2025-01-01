import {Text} from '@primer/react'

import type {PullRequest} from '../page-data/payloads/toolbar'
import {useFileViewedCountData} from '../page-data/payloads/viewed-files-count'

type ProgressIconProps = {
  progress: number
}

const ProgressIcon = ({progress}: ProgressIconProps) => {
  return (
    <svg data-circumference="38" height="16" role="presentation" style={{transform: 'rotate(-90deg)'}} width="16">
      <circle
        cx="50%"
        cy="50%"
        fill="transparent"
        r="6"
        stroke="var(--borderColor-default, var(--color-border-default))"
        strokeWidth="2"
      />
      <circle
        cx="50%"
        cy="50%"
        fill="transparent"
        r="6"
        stroke="var(--fgColor-done, var(--color-done-fg))"
        strokeDasharray={38}
        strokeDashoffset={38 - progress * 38}
        strokeLinecap="round"
        strokeWidth="2"
        style={{transition: 'stroke-dashoffset 0.35s'}}
      />
    </svg>
  )
}

export interface ViewedFileProgressProps {
  pullRequest: PullRequest
  totalFilesCount: number
  viewedFilesCount: number
}

export function ViewedFileProgress({pullRequest, totalFilesCount, ...rest}: ViewedFileProgressProps) {
  const {data: viewedFilesCount} = useFileViewedCountData(pullRequest.pathName, rest.viewedFilesCount)

  if (totalFilesCount === 0) return null

  return (
    <div className="d-flex flex-row flex-items-center">
      <ProgressIcon progress={(viewedFilesCount ?? 0) / totalFilesCount || 0} />
      <Text
        className="ml-1"
        sx={{fontSize: 0, color: 'fg.muted', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}}
      >
        <Text sx={{fontWeight: 500, color: 'fg.default'}}>{viewedFilesCount}</Text> /{' '}
        <Text sx={{fontWeight: 500, color: 'fg.default'}}>{totalFilesCount}</Text>{' '}
        <Text sx={{display: ['none', 'none', 'none', 'inline-flex']}}>viewed</Text>
      </Text>
    </div>
  )
}
