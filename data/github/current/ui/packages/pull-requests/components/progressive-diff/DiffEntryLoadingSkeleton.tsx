import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {testIdProps} from '@github-ui/test-id-props'
import {memo} from 'react'
import diffStyles from '@github-ui/diff-lines/Diff.module.css'
import {useDiffViewSettingsData} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'

export const DiffEntryLoadingSkeleton = memo(function DiffEntryLoadingSkeleton({
  ariaLabel,
  testId,
  id,
  approximateLineCount = 5,
}: {
  ariaLabel: string
  testId: string
  id?: string
  approximateLineCount?: number
}) {
  const {data: settings} = useDiffViewSettingsData()
  const heightPerLine = settings?.lineSpacing === 'compact' ? 20 : 25
  const skeletonHeight = heightPerLine * approximateLineCount
  return (
    <div className={diffStyles.diffTargetable} role="region" aria-label={ariaLabel} {...testIdProps(testId)} id={id}>
      <div className="border borderColor-muted rounded-top-2">
        <div className="d-flex flex-column gap-2 p-3" style={{minHeight: skeletonHeight}}>
          <LoadingSkeleton height={'sm'} variant="rounded" width="random" />
          <LoadingSkeleton height={'sm'} variant="rounded" width="random" />
          <LoadingSkeleton height={'sm'} variant="rounded" width="random" />
          <LoadingSkeleton height={'sm'} variant="rounded" width="random" />
        </div>
      </div>
    </div>
  )
})
