import {Blankslate} from '@primer/react/experimental'

export function FilesChangedFilterBlankSlate() {
  return (
    <div className={'color-bg-default position-relative border rounded-2 color-border-default mt-2 d-flex flex-column'}>
      <Blankslate border={false} spacious>
        <Blankslate.Heading>{'No files matched your search'}</Blankslate.Heading>
      </Blankslate>
    </div>
  )
}
