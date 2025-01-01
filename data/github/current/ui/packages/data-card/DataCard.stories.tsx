import type {Meta} from '@storybook/react'
import type {DataCardProps} from './DataCard'
import DataCard from './DataCard'
import {ActionList, ActionMenu, Link} from '@primer/react'

const meta = {
  title: 'Recipes/DataCard',
  component: DataCard,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    cardTitle: {control: 'text', defaultValue: 'Card title'},
  },
} satisfies Meta<typeof DataCard>

export default meta

const defaultArgs: Partial<DataCardProps> = {
  cardTitle: 'Card title',
}

export const DataCardCounter = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.Counter count={123} metric={{singular: 'Alert', plural: 'Alerts'}} />
      <DataCard.Description>A description</DataCard.Description>
    </DataCard>
  ),
}

export const DataCardCounterWithActionLink = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args} action={<Link href=".">View details</Link>}>
      <DataCard.Counter count={123} metric={{singular: 'Alert', plural: 'Alerts'}} />
      <DataCard.Description>A description</DataCard.Description>
    </DataCard>
  ),
}

export const DataCardCounterWithActionMenu = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard
      {...args}
      action={
        <ActionMenu>
          <ActionMenu.Button variant="invisible" size="small">
            Group by
          </ActionMenu.Button>
          <ActionMenu.Overlay>
            <ActionList>
              <ActionList.Item>Foo</ActionList.Item>
              <ActionList.Item>Bar</ActionList.Item>
              <ActionList.Item>Baz</ActionList.Item>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      }
    >
      <DataCard.Counter count={123} metric={{singular: 'Alert', plural: 'Alerts'}} />
      <DataCard.Description>A description</DataCard.Description>
    </DataCard>
  ),
}

export const DataCardCounterWithTotal = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.Counter count={123} total={345} />
      <DataCard.Description>A description</DataCard.Description>
    </DataCard>
  ),
}

export const DataCardCounterWithTotalAndMetric = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.Counter count={123} total={345} metric="limit" />
      <DataCard.Description>A description</DataCard.Description>
    </DataCard>
  ),
}
export const DataCardSingleProgress = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.ProgressBar
        data={[{progress: 30, label: "I'm a single progress bar"}]}
        aria-label={"I'm a single progress bar"}
      />
    </DataCard>
  ),
}

export const DataCardNoData = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => <DataCard {...args} />,
}

export const DataCardMultiProgress = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.ProgressBar
        aria-label={"I'm a multi progress bar"}
        data={[
          {progress: 20, label: 'First'},
          {progress: 30, label: 'Second'},
          {progress: 30, label: 'Third'},
          {progress: 10, label: 'Fourth'},
        ]}
      />
    </DataCard>
  ),
}

export const DataCardList = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.List
        data={[
          {color: 'blue', label: 'Blue', value: 10},
          {color: 'red', label: 'Red', value: 20},
          {color: 'green', label: 'Green', value: 30},
        ]}
      />
    </DataCard>
  ),
}

export const DataCardListWithProgress = {
  args: {
    ...defaultArgs,
    sx: {width: '370px'},
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.ProgressBar
        data={[
          {progress: 20, label: 'Blue'},
          {progress: 30, label: 'Green'},
          {progress: 40, label: 'Red'},
        ]}
        aria-label={"I'm a multi progress bar"}
      />
      <DataCard.List
        data={[
          {color: 'blue', label: 'Blue', value: 10},
          {color: 'red', label: 'Red', value: 20},
          {color: 'green', label: 'Green', value: 30},
        ]}
      />
    </DataCard>
  ),
}

export const DataCardDescriptionWithList = {
  args: {
    ...defaultArgs,
    sx: {width: '370px'},
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.Description>
        How long alerts across the organization take to go from open to closed for the quarter
      </DataCard.Description>
      <DataCard.List
        showPercentages
        data={[
          {label: 'Blue', value: 10},
          {label: 'Green', value: 20},
          {label: 'Red', value: 30},
          {label: 'Black', value: 10, color: 'black'}, // We can hard code a color on a progress bar if needed
        ]}
      />
    </DataCard>
  ),
}

export const DataCardCounterWide = {
  args: {
    ...defaultArgs,
  },
  render: (args: DataCardProps) => (
    <DataCard {...args}>
      <DataCard.Counter count={123} metric={{singular: 'Alert', plural: 'Alerts'}} variant="wide" />
      <DataCard.ProgressBar
        data={[{progress: 30, label: "I'm a single progress bar"}]}
        aria-label={"I'm a single progress bar"}
      />
      <DataCard.Description>A description</DataCard.Description>
    </DataCard>
  ),
}
