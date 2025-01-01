import type {Repository} from '@github-ui/current-repository'
import {noop} from '@github-ui/noop'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useRef} from 'react'

import type {CommitAppPayload, CommitPayload, DiffEntryDataWithExtraInfo, HeaderInfo} from '../../types/commit-types'
import {VirtualizedBanner} from './banners/VirtualizedBanner'
import {Diff} from './Diff'
import {DiffsHeader} from './DiffsHeader'

interface DiffsProps {
  diffEntryData: DiffEntryDataWithExtraInfo[]
  contextLinePathURL: string
  unselectedFileExtensions?: Set<string>
  repo: Repository
  oid: string
  treeToggleElement: JSX.Element
  headerInfo: HeaderInfo
  totalFileCount: number
}
export const virtualizationFileLimit = 40

export function SSRDiffs({
  diffEntryData,
  contextLinePathURL,
  repo,
  oid,
  treeToggleElement,
  headerInfo,
  totalFileCount,
}: DiffsProps) {
  const diffEntriesToUse = useRef(diffEntryData)
  const payload = useAppPayload<CommitAppPayload>()
  const shouldShowFlash = totalFileCount > virtualizationFileLimit
  const commitPayload = useRoutePayload<CommitPayload>()
  const {diff_ux_refresh_ssr_five: showFiveDiffs, diff_ux_refresh_ssr_ten: showTenDiffs} = useFeatureFlags()
  const diffLimit = showFiveDiffs ? 5 : showTenDiffs ? 10 : undefined

  return (
    <div data-hpc>
      {shouldShowFlash && <VirtualizedBanner />}
      <DiffsHeader treeToggleElement={treeToggleElement} headerInfo={headerInfo} />
      {diffEntryData.map((currentDiffData, index) => {
        //we don't want to render more than 5 or 10 diffs
        if (diffLimit && index >= diffLimit) return null
        return (
          <div key={currentDiffData.pathDigest} className={index === 0 ? 'pt-0' : 'pt-3'}>
            <Diff
              onOptionCollapseToggle={noop}
              diffEntryData={diffEntriesToUse}
              index={index}
              helpUrl={payload.helpUrl}
              contextLinePathURL={contextLinePathURL}
              recalcTotalHeightOfVirtualWindow={noop}
              repo={repo}
              ignoreWhitespace={commitPayload.ignoreWhitespace}
              oid={oid}
            />
          </div>
        )
      })}
    </div>
  )
}
