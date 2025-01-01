import type {Meta, StoryObj} from '@storybook/react'
import {ChartCard} from '../../ChartCard'
import type {ColumnChartProps, Theme} from '../../ChartCard/types'
import ColumnChartComponent from '../../ChartCard/ChartByType/ColumnChart'
import styles from './StackingAndThemes.stories.module.css'

const meta: Meta<typeof ColumnChartComponent> = {
  title: 'Recipes/ChartCard/Props/StackingAndThemes',
  component: ColumnChartComponent,
}

export default meta

const themes: Theme[] = ['green', 'pine', 'teal', 'cyan', 'blue', 'indigo', 'purple', 'orange']

export const Stacking: StoryObj<ColumnChartProps> = {
  args: {
    theme: 'green',
  },
  render: () => (
    <>
      {themes.map(theme => (
        <div key={theme} className={styles.Container}>
          <ChartCard key={theme} className={styles.Container}>
            <ChartCard.Title>{theme} theme</ChartCard.Title>
            <ChartCard.ColumnChart
              series={[
                {
                  name: `User A Usage ${theme}`,
                  data: [2100, 9000, 7600, 1700],
                },
                {
                  name: `User B Usage ${theme}`,
                  data: [2456, 3000, 9000, 4800],
                },
                {
                  name: `User C Usage ${theme}`,
                  data: [4334, 2578, 2467, 1234],
                },
                {
                  name: `User D Usage ${theme}`,
                  data: [2567, 4356, 6789, 1234],
                },
                {
                  name: `User E Usage ${theme}`,
                  data: [356, 4567, 1234, 6789],
                },
              ]}
              options={{
                xAxis: {
                  categories: ['low', 'medium', 'high', 'critical'],
                  title: 'Time',
                },
                yAxis: {
                  title: 'Billing',
                },
              }}
              stacking={'normal'}
              theme={theme}
              overrideOptionsNotRecommended={{
                lang: {
                  accessibility: {
                    legend: {
                      legendLabelNoTitle: `toggle series visibility, ${theme}`,
                    },
                    chartContainerLabel: `${theme}. Interactive chart.`,
                    navigator: {
                      groupLabel: `${theme} Axis zoom`,
                    },
                  },
                },
              }}
            />
          </ChartCard>
        </div>
      ))}
    </>
  ),
}
Stacking.storyName = 'Stacking And Themes'
