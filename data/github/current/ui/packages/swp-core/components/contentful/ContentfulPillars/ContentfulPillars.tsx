import {Grid, type GridColumnIndex} from '@primer/react-brand'

import {ContentfulPillar} from '../ContentfulPillar/ContentfulPillar'
import type {PrimerPillars} from '../../../schemas/contentful/contentTypes/primerPillars'

/**
 * Uses TypeScript discriminated union to ensure the component accepts either a `component`
 * or a `pillars` prop, but not both. This increases the flexibility
 * of this component by supporting either a primerPillars entry or a
 * plain array of primerComponentPillar entries.
 */
export type ContentfulPillarsProps =
  | {
      component: PrimerPillars
      pillars?: never
      asCards?: boolean
      className?: string
      pillarBgColor?: 'default' | 'subtle'
    }
  | {
      pillars: PrimerPillars['fields']['pillars']
      component?: never
      asCards?: boolean
      className?: string
      pillarBgColor?: 'default' | 'subtle'
    }

export function ContentfulPillars({component, pillars, asCards, className, pillarBgColor}: ContentfulPillarsProps) {
  const collection = component !== undefined ? component.fields.pillars : pillars

  const desktop = collection.length > 2 ? 4 : 6

  const span: {[key: string]: GridColumnIndex} = {
    xsmall: 12,
    small: 12,
    medium: 6,
    large: desktop,
    xlarge: desktop,
    xxlarge: desktop,
  }

  return (
    <Grid className={className}>
      {collection.map(pillar => (
        <Grid.Column span={span} key={pillar.fields.heading}>
          <ContentfulPillar component={pillar} asCard={asCards} bgColor={pillarBgColor} />
        </Grid.Column>
      ))}
    </Grid>
  )
}
