import type {Meta} from '@storybook/react'

import {SimpleListView} from '../../SimpleListView'
import {SimpleListHeader} from '../SimpleListHeader'

const meta: Meta = {
  title: 'Recipes/SimpleListView/SimpleListHeader',
  tags: ['autodocs'],
  component: SimpleListHeader,
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
      <SimpleListHeader>
        <SimpleListHeader.Title headingLevel="h1">Simple List Header</SimpleListHeader.Title>
      </SimpleListHeader>
    </SimpleListView>
  ),
}

export const HeaderWithMetadataHref = {
  name: 'Header with Metadata Link',
  render: () => (
    <SimpleListView>
      <SimpleListHeader>
        <SimpleListHeader.Title headingLevel="h1">Simple List Header</SimpleListHeader.Title>
        <SimpleListHeader.Metadata href="#">Metadata Link</SimpleListHeader.Metadata>
      </SimpleListHeader>
    </SimpleListView>
  ),
}

export const HeaderWithMetadataOnClick = {
  name: 'Header with Metadata Button',
  render: () => (
    <SimpleListView>
      <SimpleListHeader>
        <SimpleListHeader.Title headingLevel="h1">Simple List Header</SimpleListHeader.Title>
        <SimpleListHeader.Metadata onClick={() => {}}>Metadata Button</SimpleListHeader.Metadata>
      </SimpleListHeader>
    </SimpleListView>
  ),
}

export const HeaderWithMetadataText = {
  name: 'Header with Metadata Text',
  render: () => (
    <SimpleListView>
      <SimpleListHeader>
        <SimpleListHeader.Title headingLevel="h1">Simple List Header</SimpleListHeader.Title>
        <SimpleListHeader.Metadata>Metadata Text</SimpleListHeader.Metadata>
      </SimpleListHeader>
    </SimpleListView>
  ),
}
