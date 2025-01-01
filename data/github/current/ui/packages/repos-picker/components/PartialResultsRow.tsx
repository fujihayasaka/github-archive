import {human} from '@github-ui/formatters'

export function PartialResultsRow({itemCount, totalCount}: {itemCount: number; totalCount: number}) {
  if (itemCount >= totalCount) {
    return null
  }

  return (
    <div className="bgColor-inset px-3 py-2 fgColor-muted">
      {itemCount} of {human(totalCount)} items shown. <span className="f6">Use the search to find specific items</span>
    </div>
  )
}
