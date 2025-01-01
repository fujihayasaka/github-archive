import {LinesChangedCounterLabel} from '@github-ui/diff-file-header'
import {DiffViewSettings} from '@github-ui/diff-view-settings'
import {ArrowUpIcon} from '@primer/octicons-react'
import {Button, Heading} from '@primer/react'
import {memo, useRef} from 'react'

import {useStickyObserver} from '../../hooks/use-sticky-observer'
import type {HeaderInfo} from '../../types/commit-types'

interface DiffsHeaderProps {
  headerInfo: HeaderInfo
  treeToggleElement: JSX.Element
  searchBox?: JSX.Element
}

export const DiffsHeader = memo(DiffsHeaderUnmemoized)

function DiffsHeaderUnmemoized({treeToggleElement, headerInfo, searchBox}: DiffsHeaderProps) {
  const diffHeaderRef = useRef<HTMLDivElement>(null)
  const isStickied = useStickyObserver(diffHeaderRef)
  const hideLinesChangedClass = isStickied ? 'd-none d-sm-flex' : '' // make room for the Top button on mobile

  return (
    <div
      className={`d-flex flex-items-center flex-justify-between gap-2 pt-3 pt-lg-4 pb-2 position-sticky top-0 color-bg-default`}
      style={{zIndex: 2}}
      ref={diffHeaderRef}
    >
      <div className="d-flex flex-items-center">
        {treeToggleElement}
        <Heading as="h2" className="mx-2 f4">
          {headerInfo.filesChangedString} file{headerInfo.filesChanged > 1 ? 's' : ''} changed
        </Heading>
        <LinesChangedCounterLabel className={hideLinesChangedClass} isAddition>
          +{headerInfo.additions}
        </LinesChangedCounterLabel>
        <LinesChangedCounterLabel className={hideLinesChangedClass} isAddition={false}>
          -{headerInfo.deletions}
        </LinesChangedCounterLabel>
        <span className={`${hideLinesChangedClass} ml-2 fgColor-muted text-small`} style={{whiteSpace: 'nowrap'}}>
          lines changed
        </span>
      </div>

      <div className="d-flex gap-2 flex-items-center">
        {isStickied && <GoToTopButton />}
        {searchBox !== undefined && searchBox}
        <DiffViewSettings />
      </div>
    </div>
  )
}

const GoToTopButton = () => {
  return (
    <Button
      leadingVisual={ArrowUpIcon}
      variant="invisible"
      className="fgColor-default px-2 f6 gap-1"
      onClick={event => {
        event.preventDefault()
        window.scrollTo({top: 0, behavior: 'smooth'})
      }}
    >
      Top
    </Button>
  )
}
