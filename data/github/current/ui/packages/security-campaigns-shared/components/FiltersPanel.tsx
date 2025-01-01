import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {Text} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'

export type FiltersPanelProps = {
  query: string | null
}

export function FiltersPanel({query}: FiltersPanelProps) {
  if (!query)
    return (
      <Blankslate>
        <Blankslate.Description>
          <span className="text-center f5">No filters were stored for this campaign</span>
        </Blankslate.Description>
      </Blankslate>
    )

  return (
    <div className="width-full mt-3">
      <div className="d-flex flex-justify-between">
        <Text as="p" weight="semibold">
          Filters used in the campaign
        </Text>
        <CopyToClipboardButton ariaLabel="Copy to clipboard" textToCopy={query} />
      </div>
      {query}
    </div>
  )
}
