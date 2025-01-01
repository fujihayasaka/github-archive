import {KebabHorizontalIcon, SparkleFillIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, IconButton, Label, SegmentedControl, TextInput} from '@primer/react'
import type {Meta} from '@storybook/react'

import {SimpleListView} from '../../SimpleListView'
import {SimpleListItem} from '../SimpleListItem'
import styles from './SimpleListItem.module.css'

const meta: Meta = {
  title: 'Recipes/SimpleListView/SimpleListItem',
  tags: ['autodocs'],
  component: SimpleListItem,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    options: {
      order: ['Docs', '*'],
    },
  },
}

export default meta

export const Default = {
  name: 'Default',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Button item</SimpleListItem.Title>
          <SimpleListItem.Actions>
            <Button>Action</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}

const onLinkClick = () => alert('Link clicked')

export const LinkTitle = {
  name: 'Linked Item Title',
  render: () => <LinkTitleComponent />,
}

const LinkTitleComponent = () => {
  return (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title href="#">Linked item title</SimpleListItem.Title>
          <SimpleListItem.Description>This title is a link</SimpleListItem.Description>
        </SimpleListItem>
        <SimpleListItem>
          <SimpleListItem.Title onClick={onLinkClick}>Button item title</SimpleListItem.Title>
          <SimpleListItem.Description>This title can perform an action when clicked</SimpleListItem.Description>
        </SimpleListItem>
        <SimpleListItem>
          <SimpleListItem.Title>Unlinked title</SimpleListItem.Title>
          <SimpleListItem.Description>For comparison</SimpleListItem.Description>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  )
}

export const TitleStatus = {
  name: 'Title with Status',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Toggle switch item</SimpleListItem.Title>
          <SimpleListItem.Status>
            <Label>Ready for Work</Label>
          </SimpleListItem.Status>
          <SimpleListItem.Description>This is a short optional description</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <Button>Action</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}

export const TitleStatuses = {
  name: 'Title with multiple Statuses',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Toggle switch item</SimpleListItem.Title>
          <SimpleListItem.Status>
            <Label>Ready for Work</Label>
            <Label>In Progress</Label>
            <Label>In Progress</Label>
            <Label>In Review</Label>
            <Label>Done</Label>
            <Label>Triaging</Label>
          </SimpleListItem.Status>
          <SimpleListItem.Description>This is a short optional description</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <Button>Action</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}

export const Description = {
  name: 'Description',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Toggle switch item</SimpleListItem.Title>
          <SimpleListItem.Description>This is a short optional description</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <Button>Action</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}

export const TrailingActions = {
  name: 'Type: TrailingActions',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Action Menu item</SimpleListItem.Title>
          <SimpleListItem.Status>
            <Label>Ready for Work</Label>
            <Label>In Progress</Label>
            <Label>In Progress</Label>
            <Label>In Review</Label>
            <Label>Done</Label>
            <Label>Triaging</Label>
          </SimpleListItem.Status>
          <SimpleListItem.TrailingActions>
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton icon={KebabHorizontalIcon} aria-label="Open more actions menu" />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay>
                <ActionList>
                  <ActionList.Item onSelect={() => alert('Copy link clicked')}>
                    Copy link
                    <ActionList.TrailingVisual>⌘C</ActionList.TrailingVisual>
                  </ActionList.Item>
                  <ActionList.Item onSelect={() => alert('Quote reply clicked')}>
                    Quote reply
                    <ActionList.TrailingVisual>⌘Q</ActionList.TrailingVisual>
                  </ActionList.Item>
                  <ActionList.Item onSelect={() => alert('Edit comment clicked')}>
                    Edit comment
                    <ActionList.TrailingVisual>⌘E</ActionList.TrailingVisual>
                  </ActionList.Item>
                  <ActionList.Divider />
                  <ActionList.Item variant="danger" onSelect={() => alert('Delete file clicked')}>
                    Delete file
                    <ActionList.TrailingVisual>⌘D</ActionList.TrailingVisual>
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </SimpleListItem.TrailingActions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}
export const Segmented = {
  name: 'Type: Actions (Segmented)',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Segmented control item</SimpleListItem.Title>
          <SimpleListItem.Actions>
            <SegmentedControl size="small" aria-label="Choices">
              <SegmentedControl.Button>Choice 1</SegmentedControl.Button>
              <SegmentedControl.Button>Choice 2</SegmentedControl.Button>
            </SegmentedControl>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}

export const ItemTextInput = {
  name: 'Text Input',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Text Input</SimpleListItem.Title>
          <SimpleListItem.Description>This is an optional short description</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <TextInput aria-label="Example Test Input" />
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}

export const MultipleActions = {
  name: 'Multiple actions',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem>
          <SimpleListItem.Title>Toggle switch item</SimpleListItem.Title>
          <SimpleListItem.Actions>
            <Button>Action 1</Button>
            <Button>Action 2</Button>
            <Button>Action 3</Button>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}
export const Disabled = {
  name: 'Disabled',
  render: () => (
    <SimpleListView>
      <SimpleListView.Items>
        <SimpleListItem disabled>
          <SimpleListItem.Title>Disabled item</SimpleListItem.Title>
          <SimpleListItem.Description>This is an optional short description</SimpleListItem.Description>
          <SimpleListItem.Actions>
            <span className={styles.text}>Not set</span>
          </SimpleListItem.Actions>
        </SimpleListItem>
      </SimpleListView.Items>
    </SimpleListView>
  ),
}
export const LeadingVisual = () => (
  <SimpleListView>
    <SimpleListView.Items>
      <SimpleListItem>
        <SimpleListItem.LeadingVisual>
          <SparkleFillIcon />
        </SimpleListItem.LeadingVisual>
        <SimpleListItem.Title>Leading visual item</SimpleListItem.Title>
        <SimpleListItem.Actions>
          <Button>Action</Button>
        </SimpleListItem.Actions>
      </SimpleListItem>
    </SimpleListView.Items>
  </SimpleListView>
)
