import {ArrowSwitchIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import type {Meta} from '@storybook/react'

import {SimpleListHeader} from '../../SimpleListHeader/SimpleListHeader'
import {SimpleListItem} from '../../SimpleListItem/SimpleListItem'
import {SimpleListView} from '../../SimpleListView'

const meta = {
  title: 'Recipes/SimpleListView',
  component: SimpleListView,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof SimpleListView>

export default meta

export const DefaultExample = {
  name: 'Default',
  render: () => (
    <SimpleListView>
      <SimpleListHeader>
        <SimpleListHeader.Title headingLevel="h3">Default example</SimpleListHeader.Title>
      </SimpleListHeader>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.LeadingVisual>
            <ArrowSwitchIcon />
          </SimpleListItem.LeadingVisual>
          <SimpleListItem.Title>Example item</SimpleListItem.Title>
          <SimpleListItem.Description>This is an optional short description</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <Button>Do something</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}
