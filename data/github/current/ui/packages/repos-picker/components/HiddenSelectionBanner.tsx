import {human} from '@github-ui/formatters'
import {Banner} from '@primer/react/experimental'

export function HiddenSelectionBanner({hiddenSelectedCount}: {hiddenSelectedCount: number}) {
  if (hiddenSelectedCount === 0) {
    return null
  }

  return (
    <Banner variant="info" className="mt-2 mx-2" title="Hidden selection" hideTitle>
      {hiddenSelectedCount === 1
        ? 'Selected item hidden by search'
        : `${human(hiddenSelectedCount)} selected items hidden by search`}
    </Banner>
  )
}
