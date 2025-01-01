import {render} from '@github-ui/react-core/test-utils'
import {PersonIcon} from '@primer/octicons-react'
import {Select} from '@primer/react'
import type {ActionListItemInput} from '@primer/react/deprecated'
import {act, screen} from '@testing-library/react'
import {useState} from 'react'

import {MoveDialog} from '../../components/MoveDialog/MoveDialogExperimental'
import {type FormProps, MoveDialogForm} from '../../components/MoveDialog/MoveDialogFormExperimental'
import {DragAndDropMoveOptions} from '../../utils/types'
import {expectFlashMessage, selectBeforeExperimental, selectMoveAction, selectRow} from '../utils'

// Tell Jest to mock all timeout functions
jest.useFakeTimers()

const defaultItems = [
  {id: '1', title: 'In progress'},
  {id: '2', title: 'Todo'},
  {id: '3', title: "Won't do"},
  {id: '4', title: 'Blocked'},
  {id: '5', title: 'Done'},
]

const closeDialog = jest.fn()
const onActionChange = jest.fn()
const onSubmit = jest.fn()
const assigneeItems: ActionListItemInput[] = [
  {leadingVisual: PersonIcon, text: 'Joyce Zhu', id: 1},
  {leadingVisual: PersonIcon, text: 'Eric Bailey', id: 2},
  {leadingVisual: PersonIcon, text: 'Kendall Gassner', id: 3},
  {leadingVisual: PersonIcon, text: 'Alexis Lucio', id: 4},
]

function RenderList({
  title,
  submitButtonLabel,
  actionsLabel,
  items = defaultItems,
}: {
  title?: string
  submitButtonLabel?: string
  actionsLabel?: string
  items?: Array<{id: string; title: string}>
}) {
  const [helperText, setHelperText] = useState('Issue 0 will be moved...')
  const [selected, setSelected] = useState<ActionListItemInput[]>([])
  const [filter, setFilter] = useState('')
  const [open, setOpen] = useState(false)
  const filteredItems = assigneeItems.filter(item => item.text?.toLowerCase().startsWith(filter.toLowerCase()))
  const onChange = jest.fn((newText: string) => {
    setHelperText(newText)
  })
  const isInvalid = false
  const formProps: FormProps = {
    actionsLabel,
    onActionChange,
    actions: [
      {
        value: DragAndDropMoveOptions.AFTER,
        renderInput: (
          <MoveDialogForm.SingleSelect helperText={helperText} onChange={() => onChange('updated via Move item after')}>
            {items.map(item => (
              <Select.Option key={item.id} value={item.title}>
                {item.title}
              </Select.Option>
            ))}
          </MoveDialogForm.SingleSelect>
        ),
      },
      {
        value: DragAndDropMoveOptions.BEFORE,
        renderInput: (
          <MoveDialogForm.SingleSelect
            helperText={helperText}
            onChange={() => onChange('updated via Move item before')}
          >
            {items.map(item => (
              <Select.Option key={item.id} value={item.title}>
                {item.title}
              </Select.Option>
            ))}
          </MoveDialogForm.SingleSelect>
        ),
      },
      {
        value: DragAndDropMoveOptions.ROW,
        renderInput: (
          <MoveDialogForm.Text
            isInvalid={isInvalid}
            min={1}
            max={items.length}
            type="number"
            helperText={helperText}
            onChange={() => onChange('updated via Move to position')}
          />
        ),
      },
      {
        value: 'Start date',
        renderInput: (
          <MoveDialogForm.Date
            isInvalid={false}
            helperText={helperText}
            onChange={() => onChange('updated via Start date')}
            value={null}
          />
        ),
      },
      {
        value: 'Assignees',
        renderInput: (
          <MoveDialogForm.MultiSelect
            title="Select Assignees"
            placeholder="Select Assignees"
            isInvalid={isInvalid}
            items={filteredItems}
            open={open}
            selected={selected}
            onOpenChange={setOpen}
            onSelectedChange={(selectedItems: ActionListItemInput[]) => {
              setSelected(selectedItems)
              onChange('updated via Assignees')
            }}
            onFilterChange={setFilter}
            helperText={helperText ?? 'Select users to assign...'}
          />
        ),
      },
    ],
  }

  return (
    <MoveDialog
      title={title}
      submitButtonLabel={submitButtonLabel ?? 'Move'}
      formProps={formProps}
      selectedItem={{value: 'Issue 0'}}
      onSubmit={onSubmit}
      closeDialog={closeDialog}
    />
  )
}

describe('Experimental Move Dialog', () => {
  describe('The MoveDialogForm inputs render correct html elements and labels', () => {
    it('moveDialogForm.Text is labelled when action is changed', async () => {
      render(<RenderList />)

      await selectMoveAction(DragAndDropMoveOptions.ROW)

      expect(screen.getByRole('spinbutton', {name: /Move to position */i})).toBeDefined()
    })

    it('moveDialogForm.Select is labelled when action is changed', async () => {
      render(<RenderList />)

      await selectMoveAction(DragAndDropMoveOptions.AFTER)

      expect(screen.getByRole('combobox', {name: /Move item after */i})).toBeDefined()
    })

    it('moveDialogForm.Date is labelled when action is changed', async () => {
      render(<RenderList />)

      await selectMoveAction('Start date')

      expect(screen.getByRole('button', {name: /Start date */i})).toBeDefined()
    })

    it('moveDialogForm.MultiSelect is labelled when action is changed', async () => {
      render(<RenderList />)

      await selectMoveAction('Assignees')

      expect(screen.getByRole('button', {name: /Select Assignees */i})).toBeDefined()
    })
  })

  describe('Flash feedback is updated', () => {
    it('announcement when the flash feedback span is updated via MoveDialogForm.Select', async () => {
      render(<RenderList />)

      await selectMoveAction(DragAndDropMoveOptions.BEFORE)

      await selectBeforeExperimental('Done')

      expectFlashMessage('updated via Move item before')
    })

    it('announcement when the flash feedback span is updated via MoveDialogForm.Date', async () => {
      // Increase timeout to 10 seconds
      const {user} = render(<RenderList />)

      await selectMoveAction('Start date')
      expect(screen.getByRole('button', {name: /Start date */i})).toBeDefined()
      await user.click(screen.getByRole('button', {name: /Start date */i}))

      await user.click(screen.getByTestId('next-button'))
      await user.tab()
      await user.keyboard('{ArrowRight}')

      await user.keyboard('{Enter}')
      expect(screen.getByRole('button', {name: /Apply */i})).toBeEnabled()
      await user.click(screen.getByRole('button', {name: /Apply/i}))

      expectFlashMessage('updated via Start date')
    })

    it('announcement when the flash feedback span is updated via MoveDialogForm.MultiSelect', async () => {
      // Mocking console.error to prevent the following error from being logged causing tests to fail:
      // you cannot have a form within a form (SelectPanel renders a form)
      // Please remove `jest.spyOn(console, 'error').mockImplementation(() => {})` when the issue is resolved
      jest.spyOn(console, 'error').mockImplementation(() => {})
      const {user} = render(<RenderList />)

      await selectMoveAction('Assignees')
      await user.click(screen.getByRole('button', {name: /Select Assignees/i}))
      await user.click(screen.getByRole('option', {name: 'Eric Bailey'}))

      expectFlashMessage('updated via Assignees')
    })

    it('announcement when the flash feedback span is updated via MoveDialogForm.Text', async () => {
      render(<RenderList />)

      await selectMoveAction(DragAndDropMoveOptions.ROW)
      await act(async () => {
        await selectRow(2)
      })
      expectFlashMessage('updated via Move to position')
    })
  })

  describe('options render correctly', () => {
    it('flash bannner', () => {
      render(<RenderList />)

      // expect flash banner to be assertive
      expect(screen.getByTestId('drag-and-drop-move-dialog-flash')).toHaveAttribute('aria-live', 'assertive')
    })

    it('custom dialog label', () => {
      const {rerender} = render(<RenderList />)

      // expect form label to be required
      expect(screen.getByRole('form', {name: /Move Selected item */i})).toBeDefined()
      rerender(<RenderList title={'Bulk edit'} />)
      expect(screen.getByRole('form', {name: /Bulk edit */i})).toBeDefined()
    })

    it('custom submit button label', () => {
      const {rerender} = render(<RenderList />)

      // expect form label to be required
      expect(screen.getByRole('button', {name: /Move */i})).toBeDefined()
      rerender(<RenderList submitButtonLabel={'Apply'} />)
      expect(screen.getByRole('button', {name: /Apply */i})).toBeDefined()
    })

    it('custom action label', () => {
      const {rerender} = render(<RenderList />)

      // expect form label to be required
      expect(screen.getByRole('button', {name: /Move */i})).toBeDefined()
      rerender(<RenderList actionsLabel={'Field'} />)
      expect(screen.getByRole('combobox', {name: /Field */i})).toBeDefined()
    })

    it('form inputs', async () => {
      render(<RenderList />)

      expect(screen.getByRole('combobox', {name: 'Action *'})).toBeDefined()

      // check that the default value is the first action
      const option = screen.getByRole('option', {name: 'Move item after'})
      expect((option as HTMLOptionElement).selected).toBe(true)

      const moveItemAfterSelect = screen.getByRole('combobox', {name: 'Move item after *'})

      // check that the rendered input is the selected action
      expect(moveItemAfterSelect).toBeDefined()

      // check that the required attribute is set
      expect((moveItemAfterSelect as HTMLSelectElement).required).toBe(true)

      // select a text input
      await selectMoveAction(DragAndDropMoveOptions.ROW)
      const moveItemToRowInput = screen.getByRole('spinbutton', {name: 'Move to position *'})

      // check that the rendered input is the selected action
      expect(moveItemToRowInput).toBeDefined()
      // check that the required attribute is set
      expect((moveItemToRowInput as HTMLInputElement).required).toBeDefined()

      // select a date input
      await selectMoveAction('Start date')

      const startDateInput = screen.getByRole('button', {name: /Start date */i})
      // check that the rendered input is the selected action
      expect(startDateInput).toBeDefined()
      // TODO: check that the required attribute is set
      // expect((startDateInput as HTMLButtonElement).required).toBeDefined()

      // select a multi select input
      await selectMoveAction('Assignees')
      const selectAssigneesButton = screen.getByRole('button', {name: /Select Assignees */i})
      // check that the rendered input is the selected action
      expect(selectAssigneesButton).toBeDefined()
      // TODO: check that the required attribute is set
      // expect((selectAssigneesButton as HTMLButtonElement).required).toBeDefined()
    })

    it('onSubmit was called', async () => {
      const {user} = render(<RenderList />)
      await selectMoveAction(DragAndDropMoveOptions.ROW)
      await act(async () => {
        await selectRow(2)
      })
      await user.click(screen.getByRole('button', {name: /Move */i}))
      expect(onSubmit).toHaveBeenCalled()
    })

    it('closeDialog was called', async () => {
      const {user} = render(<RenderList />)
      await selectMoveAction(DragAndDropMoveOptions.ROW)
      await act(async () => {
        await selectRow(2)
      })
      await user.click(screen.getByRole('button', {name: /close */i}))
      expect(closeDialog).toHaveBeenCalled()
    })

    it('onActionChange was called', async () => {
      render(<RenderList />)
      await selectMoveAction(DragAndDropMoveOptions.ROW)

      expect(onActionChange).toHaveBeenCalled()
    })
  })
})
