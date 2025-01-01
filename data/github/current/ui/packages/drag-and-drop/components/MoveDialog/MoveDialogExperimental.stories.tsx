import {IssueOpenedIcon, PersonIcon} from '@primer/octicons-react'
import type {SelectPanelProps} from '@primer/react'
import type {ActionListItemInput} from '@primer/react/deprecated'
import type {Meta, StoryObj} from '@storybook/react'
import React, {useEffect, useMemo, useState} from 'react'

import styles from '../DragAndDrop.stories.module.css'
import {MoveDialog} from './MoveDialogExperimental'
import {type FormProps, MoveDialogForm} from './MoveDialogFormExperimental'

const meta: Meta<typeof MoveDialog> = {
  title: 'Utilities/DragAndDrop/Experimental/MoveDialog',
  component: MoveDialog,
}

const Color = ['red', 'green', 'blue']

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

type Story = StoryObj<typeof MoveDialog>

export const SortableListMoveDialog: Story = {
  render: () =>
    React.createElement(() => {
      const items = [
        {id: '0', title: 'Issue 0'},
        {id: '1', title: 'Issue 1'},
        {id: '2', title: 'Issue 2'},
      ]
      const [helperText, setHelperText] = useState<string | undefined>(undefined)
      const [isInvalid, setIsInvalid] = useState<boolean>(false)

      const formProps: FormProps = useMemo(
        () => ({
          actions: [
            {
              value: 'Move item after',
              renderInput: (
                <MoveDialogForm.SingleSelect
                  helperText={helperText ?? `Issue 0 will be moved...`}
                  onChange={e => {
                    const selectedValue = e.target.value
                    if (selectedValue === '' || selectedValue === undefined) {
                      setHelperText(`Issue 0 will be moved...`)
                      return
                    }
                    if (selectedValue === 'Issue 2') {
                      setHelperText(`Issue 0 will be the last item in the list, after Issue 2.`)
                      return
                    }
                    if (selectedValue === 'Issue 1') {
                      setHelperText(`Issue 0 will be placed between Issue 1 and Issue 2.`)
                      return
                    }
                    setHelperText(`Issue 0 cannot be moved to an invalid position.`)
                    return
                  }}
                >
                  <MoveDialogForm.SingleSelectOption value="Issue 1">Issue 1</MoveDialogForm.SingleSelectOption>
                  <MoveDialogForm.SingleSelectOption value="Issue 2">Issue 2</MoveDialogForm.SingleSelectOption>
                </MoveDialogForm.SingleSelect>
              ),
            },
            {
              value: 'Move item before',
              renderInput: (
                <MoveDialogForm.SingleSelect
                  helperText={helperText ?? `Issue 0 will be moved...`}
                  onChange={e => {
                    const selectedValue = e.target.value
                    if (selectedValue === '' || selectedValue === undefined) {
                      setHelperText(`Issue 0 will be moved...`)
                      return
                    }
                    if (selectedValue === 'Issue 1') {
                      setHelperText(`Issue 0 will be the first item in the list, before Issue 1.`)
                      return
                    }
                    if (selectedValue === 'Issue 2') {
                      setHelperText(`Issue 0 will be placed between Issue 1 and Issue 2.`)
                      return
                    }
                    setHelperText(`Issue 0 cannot be moved to an invalid position.`)
                    return
                  }}
                >
                  <MoveDialogForm.SingleSelectOption value="Issue 1">Issue 1</MoveDialogForm.SingleSelectOption>
                  <MoveDialogForm.SingleSelectOption value="Issue 2">Issue 2</MoveDialogForm.SingleSelectOption>
                </MoveDialogForm.SingleSelect>
              ),
            },
            {
              value: 'Move to position',
              renderInput: (
                <MoveDialogForm.Text
                  isInvalid={isInvalid}
                  helperText={helperText ?? `Issue 0 will be moved...`}
                  onChange={e => {
                    const selectedValue = e.target.value
                    if (selectedValue === '' || selectedValue === undefined) {
                      setHelperText(`Issue 0 will be moved...`)
                      setIsInvalid(false)
                      return
                    }
                    if (
                      Number(selectedValue) === 0 ||
                      Number(selectedValue) > 3 ||
                      Number.isNaN(Number(selectedValue))
                    ) {
                      setHelperText(`Issue 0 cannot be moved to an invalid position. The entry should be between 1-3`)
                      setIsInvalid(true)
                      return
                    }
                    setIsInvalid(false)
                    setHelperText(`Issue 0 will be moved to position ${selectedValue}`)
                    return
                  }}
                />
              ),
            },
          ],
        }),
        [helperText, isInvalid],
      )

      return (
        <>
          {items.map(item => (
            <div key={Number(item.id)} className={styles.Box_1}>
              <div className={`${styles.Box_0} ${styles.Box_2}`}>
                <ColoredCircle id={Number(item.id)} />
                {item.title}
              </div>
            </div>
          ))}
          <MoveDialog
            formProps={formProps}
            selectedItem={{value: 'Issue 0'}}
            closeDialog={() => {
              alert('close dialog was triggered')
            }}
          />
        </>
      )
    }),
}

const assigneeItems: ActionListItemInput[] = [
  {leadingVisual: PersonIcon, text: 'Joyce Zhu', id: 1},
  {leadingVisual: PersonIcon, text: 'Eric Bailey', id: 2},
  {leadingVisual: PersonIcon, text: 'Kendall Gassner', id: 3},
  {leadingVisual: PersonIcon, text: 'Alexis Lucio', id: 4},
]

const selectPanelItems: ActionListItemInput[] = [
  {leadingVisual: IssueOpenedIcon, text: 'Issue 1', description: 'New feature or request', id: 1},
  {leadingVisual: IssueOpenedIcon, text: 'Issue 2', description: "Something isn't working", id: 2},
  {leadingVisual: IssueOpenedIcon, text: 'Issue 3', description: 'Good for newcomers', id: 3},
  {leadingVisual: IssueOpenedIcon, text: 'Issue 4', id: 4},
  {leadingVisual: IssueOpenedIcon, text: 'Issue 5', id: 5},
  {leadingVisual: IssueOpenedIcon, text: 'Issue 6', id: 6},
  {leadingVisual: IssueOpenedIcon, text: 'Issue 7', id: 7},
].map(item => ({...item, descriptionVariant: 'block'}))

export const BulkEditBoard: Story = {
  render: () =>
    React.createElement(() => {
      const [helperText, setHelperText] = useState<string | undefined>(undefined)
      const isInvalid = false
      const [selected, setSelected] = useState<ActionListItemInput[]>([])
      const [filter, setFilter] = useState('')
      const filteredItems = assigneeItems.filter(item => item.text?.toLowerCase().startsWith(filter.toLowerCase()))
      const [open, setOpen] = useState(false)

      // Assignee
      useEffect(() => {
        const selectedValues = selected.map(item => item.text)
        if (selectedValues.length === 0) {
          setHelperText('Select users to assign...')
          return
        }
        if (selectedValues.length === 1) {
          setHelperText(`${selectedValues[0]} will be assigned to Issue 0`)
          return
        }
        setHelperText(`${selectedValues.length} users will be assigned to Issue 0`)
      }, [selected])

      const formProps: FormProps = {
        onActionChange: () => {
          setHelperText(undefined)
        },
        actions: [
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
                onSelectedChange={setSelected}
                onFilterChange={setFilter}
                helperText={helperText ?? 'Select users to assign...'}
              />
            ),
          },
          {
            value: 'Status',
            renderInput: (
              <MoveDialogForm.SingleSelect
                helperText={helperText ?? 'Select a status...'}
                onChange={e => {
                  const selectedValue = e.target.value
                  if (selectedValue === '' || selectedValue === undefined) {
                    setHelperText(`Select a status...`)
                    return
                  }
                  if (selectedValue === 'Remove') {
                    setHelperText('Issue 0 status will be cleared')
                  }
                  setHelperText(`${selectedValue} will be set on Issue 0`)
                  return
                }}
              >
                <MoveDialogForm.SingleSelectOption value="Remove">Remove status</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="In progress">In progress</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="To do">To do</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="Done">Done</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="Blocked">Blocked</MoveDialogForm.SingleSelectOption>
              </MoveDialogForm.SingleSelect>
            ),
          },
        ],
      }

      return (
        <MoveDialog
          formProps={formProps}
          selectedItem={{value: 'Issue 0'}}
          closeDialog={() => {
            alert('close dialog was triggered')
          }}
          submitButtonLabel="Apply"
          title="Bulk edit"
        />
      )
    }),
}

export const BulkEditIssues: Story = {
  render: () =>
    React.createElement(() => {
      const [helperText, setHelperText] = useState<string | undefined>(undefined)
      const isInvalid = false
      // State for SelectPanel controlling multiple selected input items
      const [selected, setSelected] = useState<ActionListItemInput[]>([])
      const [filter, setFilter] = useState('')
      const filteredItems = assigneeItems.filter(item => item.text?.toLowerCase().startsWith(filter.toLowerCase()))
      const [open, setOpen] = useState(false)

      // State for SelectPanel controlling multiple selected items to act upon
      const [selected2, setSelected2] = React.useState<ActionListItemInput[]>([
        selectPanelItems[0]!,
        selectPanelItems[1]!,
      ])
      const [open2, setOpen2] = useState(false)
      const [filter2, setFilter2] = React.useState('')
      const filteredItems2 = selectPanelItems.filter(item => item.text?.toLowerCase().startsWith(filter2.toLowerCase()))
      // Assignee
      useEffect(() => {
        if (selected.length === 0) {
          setHelperText('Select users to assign...')
          return
        }
        if (selected.length === 1) {
          if (selected2.length === 1) {
            setHelperText(`${selected[0]?.text} will be assigned to ${selected2[0]?.text}`)
          } else {
            setHelperText(`${selected[0]?.text} will be assigned to ${selected2.length} issues`)
          }
          return
        }
        if (selected2.length === 1) {
          setHelperText(`${selected.length} users will be assigned to ${selected2[0]?.text}`)
        } else {
          setHelperText(`${selected.length} users will be assigned to ${selected2.length} issues`)
        }
      }, [selected, selected2])

      const formProps: FormProps = {
        onActionChange: () => {
          setHelperText(undefined)
        },
        actions: [
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
                onSelectedChange={setSelected}
                onFilterChange={setFilter}
                helperText={helperText ?? 'Select users to assign...'}
              />
            ),
          },
          {
            value: 'Status',
            renderInput: (
              <MoveDialogForm.SingleSelect
                helperText={helperText ?? 'Select a status...'}
                onChange={e => {
                  const selectedValue = e.target.value
                  if (selectedValue === '' || selectedValue === undefined) {
                    setHelperText(`Select a status...`)
                    return
                  }
                  if (selectedValue === 'Remove') {
                    setHelperText('Issue status will be cleared')
                  }
                  const issueText = selected2.length === 1 ? selected2[0]?.text : `${selected2.length} issues`
                  setHelperText(`${selectedValue} will be set on ${issueText}`)
                  return
                }}
              >
                <MoveDialogForm.SingleSelectOption value="Remove">Remove status</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="In progress">In progress</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="To do">To do</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="Done">Done</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="Blocked">Blocked</MoveDialogForm.SingleSelectOption>
              </MoveDialogForm.SingleSelect>
            ),
          },
        ],
      }

      const selectPanelProps: SelectPanelProps = {
        items: filteredItems2,
        selected: selected2,
        onSelectedChange: setSelected2,
        open: open2,
        onOpenChange: setOpen2,
        onFilterChange: setFilter2,
      }

      return (
        <MoveDialog
          formProps={formProps}
          multiSelectItems
          selectPanelProps={selectPanelProps}
          closeDialog={() => {
            alert('close dialog was triggered')
          }}
        />
      )
    }),
}

export const BulkEditTimeline: Story = {
  render: () =>
    React.createElement(() => {
      const [helperText, setHelperText] = useState<string | undefined>(undefined)
      const [value, setValue] = useState(new Date())

      const formProps: FormProps = {
        onActionChange: () => {
          setHelperText(undefined)
          setValue(new Date())
        },
        actions: [
          {
            value: 'Start date',
            renderInput: (
              <MoveDialogForm.Date
                isInvalid={false}
                helperText={helperText ?? `Issue 0 start date will be changed`}
                onChange={e => {
                  const selectedValue = e?.toDateString()
                  if (selectedValue === '' || selectedValue === undefined) {
                    setHelperText(`Issue 0 start date will be changed`)
                    setValue(new Date())
                    return
                  }
                  setHelperText(`Issue 0 start date will be changed to: ${selectedValue}`)
                  if (e) {
                    setValue(e)
                  }
                  return
                }}
                value={value}
              />
            ),
          },
          {
            value: 'End date',
            renderInput: (
              <MoveDialogForm.Date
                isInvalid={false}
                helperText={helperText ?? `Issue 0 end date will be changed`}
                onChange={e => {
                  const selectedValue = e?.toDateString()
                  if (selectedValue === '' || selectedValue === undefined) {
                    setHelperText(`Issue 0 end date will be changed`)
                    setValue(new Date())
                    return
                  }
                  setHelperText(`Issue 0 end date will be changed to: ${selectedValue}`)
                  if (e) {
                    setValue(e)
                  }
                  return
                }}
                value={null}
              />
            ),
          },
        ],
      }
      return (
        <MoveDialog
          formProps={formProps}
          selectedItem={{value: 'Issue 0'}}
          closeDialog={() => {
            alert('close dialog was triggered')
          }}
          submitButtonLabel="Apply"
          title="Bulk edit"
        />
      )
    }),
}

export const NestedListViewMoveDialog: Story = {
  render: () =>
    React.createElement(() => {
      const [helperText, setHelperText] = useState<string | undefined>(undefined)
      const formProps: FormProps = {
        actions: [
          {
            value: 'Move item after',
            renderInput: (
              <MoveDialogForm.SingleSelect
                helperText={helperText ?? `Issue 0 will be moved...`}
                onChange={e => {
                  const selectedValue = e.target.value
                  if (selectedValue === '' || selectedValue === undefined) {
                    setHelperText(`Issue 0 will be moved...`)
                    return
                  }
                  if (selectedValue === 'Issue 2') {
                    setHelperText(`Issue 0 will be the last item in the list, after Issue 2.`)
                    return
                  }
                  if (selectedValue === 'Issue 1') {
                    setHelperText(`Issue 0 will be placed between Issue 1 and Issue 2.`)
                    return
                  }
                  setHelperText(`Issue 0 cannot be moved to an invalid position.`)
                  return
                }}
              >
                <MoveDialogForm.SingleSelectOption value="Issue 1">Issue 1</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="Issue 2">Issue 2</MoveDialogForm.SingleSelectOption>
              </MoveDialogForm.SingleSelect>
            ),
          },
          {
            value: 'Move item before',
            renderInput: (
              <MoveDialogForm.SingleSelect
                helperText={helperText ?? `Issue 0 will be moved...`}
                onChange={e => {
                  const selectedValue = e.target.value
                  if (selectedValue === '' || selectedValue === undefined) {
                    setHelperText(`Issue 0 will be moved...`)
                    return
                  }
                  if (selectedValue === 'Issue 1') {
                    setHelperText(`Issue 0 will be the first item in the list, before Issue 1.`)
                    return
                  }
                  if (selectedValue === 'Issue 2') {
                    setHelperText(`Issue 0 will be placed between Issue 1 and Issue 2.`)
                    return
                  }
                  setHelperText(`Issue 0 cannot be moved to an invalid position.`)
                  return
                }}
              >
                <MoveDialogForm.SingleSelectOption value="Issue 1">Issue 1</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="Issue 2">Issue 2</MoveDialogForm.SingleSelectOption>
              </MoveDialogForm.SingleSelect>
            ),
          },
          {
            value: 'Move item inside',
            renderInput: (
              <MoveDialogForm.SingleSelect
                helperText={helperText ?? `Issue 0 will be moved...`}
                onChange={e => {
                  const selectedValue = e.target.value
                  if (selectedValue === '' || selectedValue === undefined) {
                    setHelperText(`Issue 0 will be moved...`)

                    return
                  }
                  setHelperText(`Issue 0 will be moved inside of ${selectedValue}`)
                  return
                }}
              >
                <MoveDialogForm.SingleSelectOption value="Needs Triage">Needs Triage</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="P0 issues">P0 issues</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="P1 issues">P1 issues</MoveDialogForm.SingleSelectOption>
                <MoveDialogForm.SingleSelectOption value="P2 issues">P2 issues</MoveDialogForm.SingleSelectOption>
              </MoveDialogForm.SingleSelect>
            ),
          },
        ],
      }

      return (
        <MoveDialog
          formProps={formProps}
          selectedItem={{value: 'Issue 0'}}
          closeDialog={() => {
            alert('close dialog was triggered')
          }}
        />
      )
    }),
}

export default meta
