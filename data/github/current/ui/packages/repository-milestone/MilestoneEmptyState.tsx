import {Blankslate} from '@primer/react/experimental'
import {MilestoneIcon} from '@primer/octicons-react'
import {LABELS} from './constants/labels'

type MilestoneEmptyStateProps = {
  noCreatedMilestones: boolean
  newMilestoneUrl: string
}

export function MilestoneEmptyState({noCreatedMilestones, newMilestoneUrl}: MilestoneEmptyStateProps) {
  const heading = noCreatedMilestones ? LABELS.noCreatedMilestones : LABELS.weCouldntFindMilestones

  const description = noCreatedMilestones
    ? LABELS.noCreatedMilestonesDescription
    : LABELS.weCouldntFindMilestonesDescription

  return (
    <Blankslate>
      <Blankslate.Visual>
        <MilestoneIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading>{heading}</Blankslate.Heading>
      <Blankslate.Description>{description}</Blankslate.Description>
      {noCreatedMilestones && (
        <Blankslate.PrimaryAction href={newMilestoneUrl}>{LABELS.createAMilestone}</Blankslate.PrimaryAction>
      )}
    </Blankslate>
  )
}
