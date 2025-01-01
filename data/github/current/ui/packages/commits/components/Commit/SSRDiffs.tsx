import type {Repository} from '@github-ui/current-repository'
import {useDiffViewSettings} from '@github-ui/diff-view-settings/contexts/DiffViewSettingsContext'
import {noop} from '@github-ui/noop'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
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
  const diffViewSettings = useDiffViewSettings()
  const diffEntriesToUse = useRef(diffEntryData)
  const payload = useAppPayload<CommitAppPayload>()
  const shouldShowFlash = totalFileCount > virtualizationFileLimit
  const commitPayload = useRoutePayload<CommitPayload>()

  return (
    <div data-hpc>
      {shouldShowFlash && <VirtualizedBanner />}
      <DiffsHeader treeToggleElement={treeToggleElement} headerInfo={headerInfo} />
      {diffEntryData.map((currentDiffData, index) => {
        return (
          <div key={currentDiffData.pathDigest} className={index === 0 ? 'pt-0' : 'pt-3'}>
            <Diff
              onOptionCollapseToggle={noop}
              prId={undefined}
              diffEntryData={diffEntriesToUse}
              index={index}
              helpUrl={payload.helpUrl}
              lineSpacing={diffViewSettings.lineSpacing}
              splitPreference={diffViewSettings.splitPreference}
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
