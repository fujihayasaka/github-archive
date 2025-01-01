import {TrashIcon} from '@primer/octicons-react'
import {Button, IconButton} from '@primer/react'
import type {Meta} from '@storybook/react'

import {SimpleListHeader} from '../components/SimpleListHeader/SimpleListHeader'
import {SimpleListItem} from '../components/SimpleListItem/SimpleListItem'
import {SimpleListView} from '../components/SimpleListView'
import ActionMenuItem from './ActionMenuExample'

const meta: Meta = {
  title: 'Recipes/SimpleListView/Examples',
  tags: ['autodocs'],
  component: SimpleListView,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
}

export default meta

export const SimpleListViewNoHeaderSection = {
  name: 'Example without header',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Link underlines</SimpleListItem.Title>
          <SimpleListItem.Description>Show or hide underlines for links within text blocks</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <Button>Manage underlines</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
        <SimpleListItem>
          <SimpleListItem.Title>Autoplay animated images</SimpleListItem.Title>
          <SimpleListItem.Description>
            Select whether animated images should play automatically.
          </SimpleListItem.Description>
          <SimpleListItem.Actions>
            <ActionMenuItem />
          </SimpleListItem.Actions>
          <SimpleListItem.TrailingActions>
            <IconButton data-testid="trash-icon-button" variant="danger" aria-label="Delete" icon={TrashIcon} />
          </SimpleListItem.TrailingActions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}

export const SimpleListViewWithHeaderSection = {
  name: 'Example with header',
  render: () => (
    <SimpleListView>
      <SimpleListHeader>
        <SimpleListHeader.Title headingLevel="h3">Settings</SimpleListHeader.Title>
        <SimpleListHeader.Metadata href="#">View all</SimpleListHeader.Metadata>
      </SimpleListHeader>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Link underlines</SimpleListItem.Title>
          <SimpleListItem.Description>Show or hide underlines for links within text blocks</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <Button>Manage underlines</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
        <SimpleListItem>
          <SimpleListItem.Title>Autoplay animated images</SimpleListItem.Title>
          <SimpleListItem.Description>
            Select whether animated images should play automatically.
          </SimpleListItem.Description>
          <SimpleListItem.Actions>
            <ActionMenuItem />
          </SimpleListItem.Actions>
          <SimpleListItem.TrailingActions>
            <IconButton data-testid="trash-icon-button" variant="danger" aria-label="Delete" icon={TrashIcon} />
          </SimpleListItem.TrailingActions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}
