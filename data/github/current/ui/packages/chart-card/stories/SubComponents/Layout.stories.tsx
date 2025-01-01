import type {Meta, StoryObj} from '@storybook/react'

import type {TrailingVisualProps} from '../../ChartCard/TrailingVisual'
import {ChartCard} from '../../ChartCard'
import type React from 'react'

const Block = (props: {children: React.ReactNode}) => {
  return (
    <div
      className="bgColor-done-muted h5 fgColor-done p-2 border borderColor-done-muted shadow-resting-small
        rounded d-flex flex-items-center flex-justify-center flex-column"
    >
      {props.children}
      <span className="sr-only">placeholder</span>
    </div>
  )
}

const meta: Meta<typeof ChartCard> = {
  title: 'Recipes/ChartCard/SubComponents/Layout',
  component: ChartCard,
}

export default meta

export const Layout: StoryObj<TrailingVisualProps> = {
  render: () => (
    <>
      <p>
        ⚠️ This is purely a visual representation that shows where each subcomponent will render in the ChartCard
        component.
      </p>
      <ChartCard>
        <ChartCard.Title>
          <Block>ChartCard.Title</Block>
        </ChartCard.Title>
        <ChartCard.LeadingVisual>
          <Block>ChartCard.LeadingVisual</Block>
        </ChartCard.LeadingVisual>
        <ChartCard.Description>
          <Block>ChartCard.Description</Block>
        </ChartCard.Description>
        <ChartCard.TrailingVisual>
          <Block>ChartCard.TrailingVisual</Block>
        </ChartCard.TrailingVisual>
        <Block>
          <p>ChartCard.LineChart or</p>
          <p>ChartCard.SplineChart or</p>
          <p>ChartCard.AreaChart or</p>
          <p>ChartCard.AreaSplineChart or</p>
          <p>ChartCard.ColumnChart or</p>
          <p>ChartCard.Chart</p>
        </Block>
      </ChartCard>
      <p>
        The first visual row of a ChartCard consists of (left to right): ChartCard.LeadingVisual; followed by ChartCard.
        Title above ChartCard.Description; finally, ChartCard.TrailingVisual. This is then followed by an instance of
        one of the LineChart, SplineChart, AreaChart, AreaSplineChart, ColumnChart, or Chart components.
      </p>
    </>
  ),
}
Layout.storyName = 'Layout'
