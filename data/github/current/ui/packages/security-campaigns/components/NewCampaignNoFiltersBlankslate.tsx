import {Blankslate} from '@primer/react/experimental'

export type NewCampaignNoFiltersBlankslateProps = {
  onAddFiltersClick: () => void
}

export function NewCampaignNoFiltersBlankslate({onAddFiltersClick}: NewCampaignNoFiltersBlankslateProps) {
  return (
    <Blankslate spacious border>
      <Blankslate.Heading>No filters defined</Blankslate.Heading>
      <Blankslate.Description>Filter alerts to start creating your campaign</Blankslate.Description>
      <Blankslate.PrimaryAction onClick={onAddFiltersClick}>Add filters</Blankslate.PrimaryAction>
    </Blankslate>
  )
}
