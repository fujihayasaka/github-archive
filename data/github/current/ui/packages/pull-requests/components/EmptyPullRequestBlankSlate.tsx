import {Blankslate} from '@primer/react/experimental'

export function EmptyPullRequestBlankSlate() {
  return (
    <div className={'color-bg-default position-relative border rounded-2 color-border-default mt-2 d-flex flex-column'}>
      <Blankslate border={false} spacious>
        <Blankslate.Heading>{'No changes to show'}</Blankslate.Heading>
        <Blankslate.Description>{'This commit does not include any file changes'}</Blankslate.Description>
      </Blankslate>
    </div>
  )
}
