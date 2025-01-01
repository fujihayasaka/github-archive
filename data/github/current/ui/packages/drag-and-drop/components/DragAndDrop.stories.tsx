import {shouldInteractionPlay} from '@github-ui/storybook'
import {ArrowSwitchIcon, GrabberIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {expect} from '@storybook/jest'
import type {Meta, StoryObj} from '@storybook/react'
import {userEvent, waitFor, within} from '@storybook/test'
import React, {useState} from 'react'

import {dragEnd, dragMove, dragStart} from '../test-utils'
import type {OnDropArgs} from '../utils/types'
import {DragAndDrop} from './DragAndDrop'
import styles from './DragAndDrop.stories.module.css'
import {KeyboardSpecificInstructionsDialog as KeyboardSpecificInstructionsDialogComponent} from './KeyboardSpecificInstructionsDialog'
import {MoveDialogTrigger} from './MoveDialog/MoveDialogTrigger'
import {SortableListTrigger} from './SortableListTrigger'

const meta: Meta<typeof DragAndDrop> = {
  title: 'Utilities/DragAndDrop',
  component: DragAndDrop,
}

type Story = StoryObj<typeof DragAndDrop>

const containerStyle = {
  borderBottom: '1px solid grey',
  display: 'flex',
}

const itemStyles = {
  display: 'grid',
  alignItems: 'center',
  gridTemplateColumns: 'min-content 1fr min-content',
  gap: '12px',
  padding: '12px',
  width: '100%',
}

const initializedItems = [
  {id: '1', title: 'In progress'},
  {id: '2', title: 'To do'},
  {id: '3', title: 'Done'},
]

const Color = ['red', 'green', 'blue', 'yellow', 'orange', 'purple', 'pink', 'brown', 'black', 'cyan']

const ColoredCircle = ({id}: {id: number}) => (
  <div
    style={{
      width: '10px',
      height: '10px',
      borderRadius: '50%',
      backgroundColor: Color[id % Color.length],
    }}
  />
)

export const BasicMouseSortableList: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(initializedItems)
      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={itemStyles}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            icon={ArrowSwitchIcon}
            variant="invisible"
            style={{transform: 'rotate(90deg)'}}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )

      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          aria-label="Drag and drop list."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)

      await step('should drag item', async () => {
        let itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('In progress')
        await expect(itemsLocator[1]).toHaveTextContent('To do')
        await expect(itemsLocator[2]).toHaveTextContent('Done')

        const keyboardTriggers = canvas.getAllByTestId('sortable-mouse-trigger')
        const firstTrigger = keyboardTriggers[0] as Element
        const secondTrigger = keyboardTriggers[1] as Element

        const {currentPosition, mouseStep} = await dragStart({element: firstTrigger, to: secondTrigger})
        await expectAnnouncement(canvasElement, 'Moving In progress.')

        const moveCurrentPosition = await dragMove(firstTrigger, currentPosition, mouseStep)
        await expectAnnouncement(canvasElement, 'Between Done and To do.')

        await dragEnd(firstTrigger, moveCurrentPosition)
        await expectAnnouncement(canvasElement, 'In progress successfully moved between Done and To do.')

        itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('To do')
        await expect(itemsLocator[1]).toHaveTextContent('In progress')
        await expect(itemsLocator[2]).toHaveTextContent('Done')
      })

      await step('should drag item to the start of the list', async () => {
        let itemsLocator = canvas.getAllByTestId('sortable-item')
        const keyboardTriggers = canvas.getAllByTestId('sortable-mouse-trigger')
        const firstTrigger = keyboardTriggers[0] as Element
        const secondTrigger = keyboardTriggers[1] as Element

        const {currentPosition, mouseStep} = await dragStart({element: secondTrigger, to: firstTrigger})
        await expectAnnouncement(canvasElement, 'Moving In progress.')

        const moveCurrentPosition = await dragMove(secondTrigger, currentPosition, mouseStep)
        await expectAnnouncement(canvasElement, 'First item in list.')

        await dragEnd(secondTrigger, moveCurrentPosition)
        await expectAnnouncement(canvasElement, 'In progress successfully moved to first item in list.')

        itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('In progress')
        await expect(itemsLocator[1]).toHaveTextContent('To do')
        await expect(itemsLocator[2]).toHaveTextContent('Done')
      })

      await step('should drag item to the end of the list', async () => {
        let itemsLocator = canvas.getAllByTestId('sortable-item')

        const keyboardTriggers = canvas.getAllByTestId('sortable-mouse-trigger')
        const firstTrigger = keyboardTriggers[0] as Element
        const thirdTrigger = keyboardTriggers[2] as Element

        const {currentPosition, mouseStep} = await dragStart({element: firstTrigger, to: thirdTrigger})
        await expectAnnouncement(canvasElement, 'Moving In progress.')

        const moveCurrentPosition = await dragMove(firstTrigger, currentPosition, mouseStep)
        await expectAnnouncement(canvasElement, 'Last item in list.')

        await dragEnd(firstTrigger, moveCurrentPosition)
        await expectAnnouncement(canvasElement, 'In progress successfully moved to last item in list.')

        itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('To do')
        await expect(itemsLocator[1]).toHaveTextContent('Done')
        await expect(itemsLocator[2]).toHaveTextContent('In progress')
      })

      await step('should cancel drag item when pressing the escape key', async () => {
        let itemsLocator = canvas.getAllByTestId('sortable-item')

        const keyboardTriggers = canvas.getAllByTestId('sortable-mouse-trigger')
        const firstTrigger = keyboardTriggers[0] as Element
        const secondTrigger = keyboardTriggers[1] as Element

        const {currentPosition, mouseStep} = await dragStart({element: firstTrigger, to: secondTrigger})
        await expectAnnouncement(canvasElement, 'Moving To do.')

        await dragMove(firstTrigger, currentPosition, mouseStep)
        await expectAnnouncement(canvasElement, 'Between In progress and Done.')

        await userEvent.keyboard('{Escape}')
        await expectAnnouncement(canvasElement, 'To do not moved.')

        itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('To do')
        await expect(itemsLocator[1]).toHaveTextContent('Done')
        await expect(itemsLocator[2]).toHaveTextContent('In progress')
      })
    }
  },
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
  tags: ['no-a11y'],
}

export const BasicSortableList: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(initializedItems)
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={itemStyles}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            icon={ArrowSwitchIcon}
            variant="invisible"
            style={{transform: 'rotate(90deg)'}}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )
      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }

      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          aria-label="Drag and drop list."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)

      await step('dismiss keyboard specific instructions dialog', async () => {
        const keyboardTrigger = canvas.getAllByTestId('sortable-trigger')[0]
        keyboardTrigger?.focus()
        await userEvent.keyboard('{Enter}') // start drag

        const keyboardSpecificInstructionsDialog = canvas.queryByRole('dialog', {
          name: 'How to move objects via keyboard',
        })
        if (keyboardSpecificInstructionsDialog) {
          const hideCheckbox = within(keyboardSpecificInstructionsDialog).getByRole('checkbox')
          await userEvent.click(hideCheckbox)

          await userEvent.keyboard('{Tab}') // focus close button
          await userEvent.keyboard('{Enter}') // close dialog
        }
        await userEvent.keyboard('{Escape}') // end drag
      })

      await step('should drag item when pressing the enter key', async () => {
        let itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('In progress')
        await expect(itemsLocator[1]).toHaveTextContent('To do')
        await expect(itemsLocator[2]).toHaveTextContent('Done')

        const keyboardTrigger = canvas.getAllByTestId('sortable-trigger')[0]
        keyboardTrigger?.focus()
        await userEvent.keyboard('{Enter}') // start drag
        await expectAnnouncement(canvasElement, 'First item in list.')
        await userEvent.keyboard('{ArrowDown}') // move item one down
        await expectAnnouncement(canvasElement, 'Between Done and To do.')

        await userEvent.keyboard('{Enter}')
        await expectAnnouncement(canvasElement, 'In progress successfully moved between Done and To do.')

        itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('To do')
        await expect(itemsLocator[1]).toHaveTextContent('In progress')
        await expect(itemsLocator[2]).toHaveTextContent('Done')
      })

      await step('should drag item when pressing the space key', async () => {
        const keyboardTrigger = canvas.getAllByTestId('sortable-trigger')[0]
        keyboardTrigger?.focus()
        await userEvent.keyboard(' ') // start drag
        await expectAnnouncement(canvasElement, 'Moving To do.')
        await userEvent.keyboard('{ArrowDown}') // move item one down
        await expectAnnouncement(canvasElement, 'Between Done and In progress.')

        await userEvent.keyboard(' ')
        await expectAnnouncement(canvasElement, 'To do successfully moved between Done and In progress.')

        const itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('In progress')
        await expect(itemsLocator[1]).toHaveTextContent('To do')
        await expect(itemsLocator[2]).toHaveTextContent('Done')
      })

      await step('should drag item to the start of the list', async () => {
        const keyboardTrigger = canvas.getAllByTestId('sortable-trigger')[1]
        keyboardTrigger?.focus()
        await userEvent.keyboard('{Enter}') // start drag
        await expectAnnouncement(canvasElement, 'Moving To do.')
        await userEvent.keyboard('{ArrowUp}') // move item one down
        await expectAnnouncement(canvasElement, 'First item in list.')

        await userEvent.keyboard('{Enter}')
        await expectAnnouncement(canvasElement, 'To do successfully moved to first item in list.')

        const itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('To do')
        await expect(itemsLocator[1]).toHaveTextContent('In progress')
        await expect(itemsLocator[2]).toHaveTextContent('Done')
      })

      await step('should drag item to the end of the list', async () => {
        const keyboardTrigger = canvas.getAllByTestId('sortable-trigger')[0]
        keyboardTrigger?.focus()
        await userEvent.keyboard('{Enter}') // start drag
        await expectAnnouncement(canvasElement, 'First item in list.')
        await userEvent.keyboard('{ArrowDown}') // move item one down
        await userEvent.keyboard('{ArrowDown}') // move item one down

        await expectAnnouncement(canvasElement, 'Last item in list.')

        await userEvent.keyboard('{Enter}')
        await expectAnnouncement(canvasElement, 'To do successfully moved to last item in list.')

        const itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('In progress')
        await expect(itemsLocator[1]).toHaveTextContent('Done')
        await expect(itemsLocator[2]).toHaveTextContent('To do')
      })

      await step('should cancel drag item when pressing the escape key', async () => {
        const keyboardTrigger = canvas.getAllByTestId('sortable-trigger')[0]
        keyboardTrigger?.focus()
        await userEvent.keyboard('{Enter}') // start drag
        await expectAnnouncement(canvasElement, 'First item in list.')
        await userEvent.keyboard('{ArrowDown}') // move item one down
        await expectAnnouncement(canvasElement, 'Between To do and Done.')

        await userEvent.keyboard('{Escape}') // end drag

        await expectAnnouncement(canvasElement, 'In progress not moved.')

        const itemsLocator = canvas.getAllByTestId('sortable-item')
        await expect(itemsLocator[0]).toHaveTextContent('In progress')
        await expect(itemsLocator[1]).toHaveTextContent('Done')
        await expect(itemsLocator[2]).toHaveTextContent('To do')
      })

      await step('should lock focus on drag handle when being dragged', async () => {
        const keyboardTrigger = canvas.getAllByTestId('sortable-trigger')[0]
        keyboardTrigger?.focus()
        await userEvent.keyboard('{Enter}') // start drag
        await expectAnnouncement(canvasElement, 'First item in list.')
        await userEvent.keyboard('{Tab}') // move item one down

        await expect(keyboardTrigger).toHaveFocus()
        await userEvent.keyboard('{Escape}') // cancel drag mode
        await userEvent.keyboard('{Tab}') // try to focus out
        await expect(keyboardTrigger).not.toHaveFocus()
      })
    }
  },
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
  tags: ['no-a11y'],
}

async function expectAnnouncement(canvas: HTMLElement, text: string) {
  const announcement = within(canvas).getByTestId('sr-assertive')
  await waitFor(() => expect(announcement).toHaveTextContent(text))
}

export const LongSortableList: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(() => [...Array(60).keys()].map(i => ({id: i.toString(), title: `Item ${i}`})))
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={itemStyles}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            icon={ArrowSwitchIcon}
            variant="invisible"
            style={{transform: 'rotate(90deg)'}}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )
      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }
      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          aria-label="Drag and drop list."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

export const SingleItemSortableList: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(initializedItems[0] ? [initializedItems[0]] : [])
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={itemStyles}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            icon={ArrowSwitchIcon}
            variant="invisible"
            style={{transform: 'rotate(90deg)'}}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )

      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }

      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          aria-label="Drag and drop list with a single item."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

export const VariableHeightsSortableList: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(() => [
        {id: '1', title: 'Gravida quis blandit turpis cursus in hac habitasse platea dictumst.'},
        {
          id: '2',
          title:
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
        },
        {
          id: '3',
          title:
            'Magna fringilla urna porttitor rhoncus. Volutpat lacus laoreet non curabitur gravida. Commodo nulla facilisi nullam vehicula ipsum a arcu. Sed elementum tempus egestas sed sed. Venenatis tellus in metus vulputate eu scelerisque felis imperdiet proin. ',
        },
      ])
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={itemStyles}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            icon={ArrowSwitchIcon}
            variant="invisible"
            style={{transform: 'rotate(90deg)'}}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )

      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }

      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          aria-label="Drag and drop list with variable height items."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

export const CustomSortableListTrigger: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(initializedItems)
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          hideSortableItemTrigger
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={{...itemStyles, gridTemplateColumns: '1fr min-content  min-content'}}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <SortableListTrigger />
          <ActionMenu>
            <ActionMenu.Button>Open menu</ActionMenu.Button>
            <ActionMenu.Overlay width="medium">
              <ActionList>
                <MoveDialogTrigger Component={ActionList.Item} aria-label={`Advanced Move ${item.title}`}>
                  {/* False positive I am using an ActionList.Item */}
                  {/* eslint-disable-next-line primer-react/direct-slot-children */}
                  <ActionList.LeadingVisual>
                    <GrabberIcon />
                  </ActionList.LeadingVisual>
                  Advanced Move...
                </MoveDialogTrigger>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </DragAndDrop.Item>
      )

      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }

      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          aria-label="Drag and drop list with custom sortable list trigger."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

const HorizontalContainer = {
  display: 'grid',
  gridTemplateColumns: 'repeat(3, 1fr)',
  width: '100%',
  gridAutoFlow: 'column',
}

export const HorizontalList: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(initializedItems)
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={itemStyles}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            variant="invisible"
            icon={ArrowSwitchIcon}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )

      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }
      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          direction={'horizontal'}
          style={HorizontalContainer}
          aria-label="Horizontal drag and drop list."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

export const LongHorizontalList: Story = {
  render: () =>
    React.createElement(() => {
      const [items, setItems] = useState(() => [...Array(60).keys()].map(i => ({id: i.toString(), title: `Item ${i}`})))
      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={containerStyle}
          style={itemStyles}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            variant="invisible"
            icon={ArrowSwitchIcon}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )
      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }
        const dragItem = items.find(item => item.id === dragMetadata.id)
        if (dragItem) {
          setItems(
            items.reduce(
              (newItems, item) => {
                if (dragItem.id === item.id) {
                  return newItems
                }
                if (item.id !== dropMetadata?.id) {
                  newItems.push(item)
                } else if (isBefore) {
                  newItems.push(dragItem, item)
                } else {
                  newItems.push(item, dragItem)
                }
                return newItems
              },
              [] as typeof items,
            ),
          )
        }
      }
      return (
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          direction={'horizontal'}
          style={HorizontalContainer}
          aria-label="Long horizontal drag and drop list."
          renderOverlay={(item, index) => Row(item, index, true)}
        >
          {items.map((item, index) => Row(item, index, false))}
        </DragAndDrop>
      )
    }),
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

export const KeyboardSpecificInstructionsDialog: Story = {
  render: () => <KeyboardSpecificInstructionsDialogComponent isOpen onClose={() => {}} direction="vertical" />,
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

export const ParentAndChildList: Story = {
  render: () =>
    React.createElement(() => {
      type Row = {id: string; title: string}
      const [columns, setItems] = useState(() =>
        [...Array(3).keys()].map(i => ({id: i.toString(), title: `Column ${i}`})),
      )
      const [rows0, setRows0] = useState(
        [...Array(10).keys()].map(i => ({id: `1000${i.toString()}`, title: `Row ${i}`})),
      )
      const [rows1, setRows1] = useState(
        [...Array(10).keys()].map(i => ({id: `2000${i.toString()}`, title: `Row ${i}`})),
      )
      const [rows2, setRows2] = useState(
        [...Array(10).keys()].map(i => ({id: `3000${i.toString()}`, title: `Row ${i}`})),
      )

      const rowArray: Row[][] = []
      rowArray.push(rows0)
      rowArray.push(rows1)
      rowArray.push(rows2)

      const Row = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={{...containerStyle}}
          style={{...itemStyles}}
        >
          <div className={styles.Box_0}>
            <ColoredCircle id={Number(item.id)} />
            {item.title}
          </div>
          <MoveDialogTrigger
            Component={IconButton}
            variant="invisible"
            style={{transform: 'rotate(90deg)'}}
            icon={ArrowSwitchIcon}
            aria-label={`Advanced move ${item.title}...`}
          />
        </DragAndDrop.Item>
      )

      const Column = (item: {id: string; title: string}, index: number, isDragOverlay: boolean) => (
        <DragAndDrop.Item
          hideSortableItemTrigger
          isDragOverlay={isDragOverlay}
          index={index}
          id={item.id}
          key={item.id}
          title={item.title}
          containerStyle={{display: 'flex', justifyContent: 'center'}}
          style={{
            display: 'flex',
            gap: '12px',
            flexDirection: 'column',
            justifyContent: 'center',
            border: '1px solid var(--fgColor-muted)',
            borderRadius: '6px 6px 0px  0px',
            width: '100%',
          }}
        >
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              gap: '12px',
              borderBottom: '1px solid var(--fgColor-muted)',
            }}
          >
            <SortableListTrigger />
            <div className={styles.Box_0}>{item.title}</div>
            <MoveDialogTrigger
              Component={IconButton}
              variant="invisible"
              icon={ArrowSwitchIcon}
              aria-label={`Advanced move ${item.title}...`}
            />
          </div>
          <div style={{display: 'flex', justifyContent: 'center', width: '100%'}}>
            {createRowsDnD(rowArray[index] ?? [])}
          </div>
        </DragAndDrop.Item>
      )

      const createRowsDnD = (rows: Row[]) => {
        return (
          <DragAndDrop
            items={rows}
            onDrop={onDrop}
            direction={'vertical'}
            style={{display: 'flex', flexDirection: 'column', gap: '8px', width: '100%'}}
            aria-label="Child rows drag and drop list."
            renderOverlay={(item, index) => Row(item, index, true)}
          >
            {rows.map((item, index) => Row(item, index, false))}
          </DragAndDrop>
        )
      }

      const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
        if (dragMetadata.id === dropMetadata?.id) {
          return
        }

        const setOnDrag = (items: typeof columns, setFunc: typeof setItems) => {
          const dragItem = items.find(item => item.id === dragMetadata.id)
          if (dragItem) {
            setFunc(
              items.reduce(
                (newItems, item) => {
                  if (dragItem.id === item.id) {
                    return newItems
                  }
                  if (item.id !== dropMetadata?.id) {
                    newItems.push(item)
                  } else if (isBefore) {
                    newItems.push(dragItem, item)
                  } else {
                    newItems.push(item, dragItem)
                  }
                  return newItems
                },
                [] as typeof columns,
              ),
            )
          }
        }

        setOnDrag(columns, setItems)
        setOnDrag(rows0, setRows0)
        setOnDrag(rows1, setRows1)
        setOnDrag(rows2, setRows2)
      }
      return (
        <DragAndDrop
          items={columns}
          onDrop={onDrop}
          direction={'horizontal'}
          style={HorizontalContainer}
          aria-label="Parent columns drag and drop list."
          renderOverlay={(item, index) => Column(item, index, true)}
        >
          {columns.map((item, index) => Column(item, index, false))}
        </DragAndDrop>
      )
    }),
  parameters: {
    enabledFeatures: ['drag_and_drop_experimental_move_dialog'],
  },
}

export default meta
