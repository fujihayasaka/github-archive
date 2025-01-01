import {Stack} from '@primer/react'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'

export function RowLoading(): JSX.Element {
  function randomLabelWidth(): string {
    const min = 40
    const max = 60
    const randomWidth = Math.floor(Math.random() * (max - min + 1) + min)
    return `${randomWidth}%`
  }

  return (
    <Stack direction="horizontal" gap="condensed" className="px-3 py-2 border-bottom color-border-muted">
      <LoadingSkeleton variant="elliptical" height="md" width="md" />
      <Stack className="width-full">
        <LoadingSkeleton variant="rounded" height="sm" width={randomLabelWidth()} />
        <LoadingSkeleton variant="rounded" height="12px" width={randomLabelWidth()} className="mt-2" />
      </Stack>
    </Stack>
  )
}
