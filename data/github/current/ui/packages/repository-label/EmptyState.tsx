import {TagIcon} from '@primer/octicons-react'
import {LABELS} from './constants/labels'
import {Blankslate} from '@primer/react/experimental'

export const EmptyState = ({
  noLabelsCreated,
  viewerCanPush,
  onCreateLabel,
}: {
  noLabelsCreated: boolean
  viewerCanPush: boolean
  onCreateLabel?: () => void
}) => {
  const title = noLabelsCreated ? LABELS.noLabelsCreatedTitle : LABELS.noMatchingLabelsTitle
  const description =
    noLabelsCreated && viewerCanPush ? LABELS.noLabelsCreatedDescription : LABELS.noMatchingLabelsDescription
  return (
    <Blankslate>
      <Blankslate.Visual>
        <TagIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading as="h3">{title}</Blankslate.Heading>
      <Blankslate.Description>{description}</Blankslate.Description>
      {noLabelsCreated && viewerCanPush && (
        <Blankslate.PrimaryAction onClick={onCreateLabel}>{LABELS.newLabel}</Blankslate.PrimaryAction>
      )}
    </Blankslate>
  )
}
