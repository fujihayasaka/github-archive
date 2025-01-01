import type {Meta} from '@storybook/react'
import type {ComponentType} from 'react'
import type React from 'react'

import {SimpleListItem} from '../components/SimpleListItem/SimpleListItem'
import {SimpleListView} from '../components/SimpleListView'

const meta: Meta<
  | typeof SimpleListView
  | ComponentType<{
      titleText: string
      descriptionText: string
      titleAs: string
      children: React.ReactNode
    }>
> = {
  title: 'Recipes/SimpleListView/Playground',
  component: SimpleListView,
  argTypes: {
    titleText: {
      name: 'children',
      value: 'Toggle switch item with a lot longer of a description',
      control: {
        type: 'text',
      },
      table: {
        category: 'SimpleListItemTitle',
      },
    },
    descriptionText: {
      name: 'children',
      value: 'This is an optional short description',
      control: {
        type: 'text',
      },
      table: {
        category: 'SimpleListItemDescription',
      },
    },
    titleAs: {
      name: 'as',
      control: {
        type: 'select',
      },
      options: ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'],
      table: {
        category: 'SimpleListItemTitle',
      },
    },
  },
  args: {
    titleText: 'SimpleListView item title',
    descriptionText: 'This is an optional short description',
    titleAs: 'h3',
  },
}

export default meta

type Args = {
  titleText: string
  descriptionText: string
  titleAs: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
}

export const SimpleListViewPlayground = (args: Args) => (
  <SimpleListView>
    <SimpleListView.Items>
      <SimpleListItem>
        <SimpleListItem.Title>{args.titleText}</SimpleListItem.Title>
        <SimpleListItem.Description>{args.descriptionText}</SimpleListItem.Description>
        <SimpleListItem.Actions>Custom action</SimpleListItem.Actions>
      </SimpleListItem>
    </SimpleListView.Items>
  </SimpleListView>
)
SimpleListViewPlayground.storyName = 'Item'
