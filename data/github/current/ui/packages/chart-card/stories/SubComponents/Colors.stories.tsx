import type React from 'react'
import type {Meta, StoryObj} from '@storybook/react'
import type {MarkColor} from '../../ChartCard/types'

import styles from './Colors.stories.module.css'
import {LineDefaultColor} from '../../ChartCard/ChartByType/LineChart'
import {AreaDefaultColor} from '../../ChartCard/ChartByType/AreaChart'
import {ColumnDefaultColor} from '../../ChartCard/ChartByType/ColumnChart'

// Simple marker component to display color
const ColorMarker: React.FC<{color: MarkColor; name: string}> = ({color, name}) => (
  <div className={styles.ColorContainer}>
    <div
      className={styles.ColorBox}
      style={{
        background: `var(${color})`,
      }}
    />
    <h3 className={styles.ColorName}>{name}</h3>
    <code>{color}</code>
  </div>
)

const ColorList: React.FC = () => (
  <div className={styles.Container}>
    <h2>Default LineChart and SplineChart Theme:</h2>
    <div className={styles.ColorList}>
      {Object.entries(LineDefaultColor).map(([name, color]) => (
        <ColorMarker key={name} color={color} name={name} />
      ))}
    </div>
    <h2>Default AreaChart and AreaSplineChart Theme:</h2>
    <div className={styles.ColorList}>
      {Object.entries(AreaDefaultColor).map(([name, color]) => (
        <ColorMarker key={name} color={color} name={name} />
      ))}
    </div>
    <h2>Default ColumnChart and BarChart Theme:</h2>
    <div className={styles.ColorList}>
      {Object.entries(ColumnDefaultColor).map(([name, color]) => (
        <ColorMarker key={name} color={color} name={name} />
      ))}
    </div>
  </div>
)

const meta: Meta<typeof ColorList> = {
  title: 'Recipes/ChartCard/SubComponents/ChartThemes',
  component: ColorList,
}

export default meta

type Story = StoryObj<typeof ColorList>

export const ChartThemes: Story = {
  render: () => <ColorList />,
}

ChartThemes.storyName = 'ChartThemes'
