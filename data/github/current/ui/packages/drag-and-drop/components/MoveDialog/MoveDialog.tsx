/***
 * STATUS: Experimental - This component is not ready for production
 * The Accessibility Team is actively working on this component.
 * Please reach out to #accessibility with any questions.
 */

import {announce} from '@github-ui/aria-live'
import {testIdProps} from '@github-ui/test-id-props'
import {AlertIcon, InfoIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button, Flash, FormControl, SelectPanel, type SelectPanelProps, useOnOutsideClick} from '@primer/react'
import type {ActionListItemInput} from '@primer/react/deprecated'
import {Dialog} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {type FormEvent, useId, useRef, useState} from 'react'

import {DragAndDropResources} from '../../utils/strings'
import styles from './MoveDialog.module.css'
import type {FormProps} from './MoveDialogForm'
import {MoveDialogForm} from './MoveDialogForm'

const MOVE_DIALOG_TITLE_ID = 'move-dialog-title'
export interface MoveDialogBaseProps {
  /**
   * The props for the form that is rendered in the dialog
   */
  formProps: FormProps
  /**
   * Callback to close the dialog
   */
  closeDialog: () => void
  /**
   * Optional: label for the submit button
   */
  submitButtonLabel?: string
  /**
   *  Optional: The label for the dialog
   */
  title?: string
  /**
   *  Optional: Callback to submit the dialog
   */
  onSubmit?: (event: FormEvent) => void | Promise<void>
  /**
   * Optional: The ref to return focus to when the dialog is closed
   */
  returnFocusRef?: React.RefObject<HTMLElement>
}

export interface MoveDialogPropsSingleSelect {
  /**
   * The selected item that the user is moving
   */
  selectedItem: {
    value: string
  }
  multiSelectItems?: false
}

export interface MoveDialogPropsMultiSelect {
  multiSelectItems: true
  /**
   * Note that the selected items may be derived from the select panel's "selected" props
   */
  selectPanelProps: SelectPanelProps
}

export type MoveDialogProps = MoveDialogBaseProps & (MoveDialogPropsSingleSelect | MoveDialogPropsMultiSelect)

/**
 * A dialog that allows the user to move an item to a new position in the list.
 *
 * @param props MoveDialogProps
 */
export const MoveDialog = ({
  closeDialog,
  onSubmit: onSubmitProp,
  formProps,
  title,
  submitButtonLabel,
  returnFocusRef,
  ...rest
}: MoveDialogProps) => {
  // TODO: pass setIsInvalid to the form
  const [isInvalidOption, setIsInvalidOption] = useState(false)
  const [showErrorDialog, setShowErrorDialog] = useState(false)

  let singleSelectedItemValue = ''
  let firstSelectedMultiselectItem: ActionListItemInput | undefined

  // We can't destructure `multiSelectItems` out of `rest` in the props type signature because TS then can't figure out if
  // it should expect `selectedItems` or `selectedItem` in the resulting object without type coercion.
  if (!rest.multiSelectItems) {
    singleSelectedItemValue = rest.selectedItem.value
  } else {
    const initiallySelectedItems = rest.selectPanelProps.selected as ActionListItemInput[]
    firstSelectedMultiselectItem = initiallySelectedItems[0]
  }
  const [helperText, setHelperText] = useState('')

  const helperTextId = useId()

  const containerRef = useRef<HTMLDivElement>(null)

  // Dialog doesn't use Overlay or call `useOnOutsideClick` under the hood. This means that
  // it doesn't get registered as an overlay in the stack, which means it doesn't intercept
  // and stop propagating clicks. This means that if there are any open `Overlay`s underneath
  // this `Dialog`, clicks in this dialog will register as clicks outside of those overlays,
  // causing them to try to close.
  // We can prevent this by registering a fake `useOnClickOutside` hook to make this look like
  // a regular `Overlay`. Clicks inside will no-op and the hook will prevent them from propagating
  // to other overlays; clicks outside need to have `preventDefault` called on them to stop them
  // from propagating.
  useOnOutsideClick({containerRef, onClickOutside: e => e.preventDefault()})

  const onSubmit = async (event: FormEvent) => {
    event.preventDefault() // prevent page reload
    // checkVal
    if (isInvalidOption) {
      const invalidField = containerRef.current?.querySelector('[aria-invalid="true"]')
      if (invalidField) (invalidField as HTMLInputElement).focus()
      return
    }
    await onSubmitProp?.(event)
  }

  const onSelectedChange = (selected: ActionListItemInput[]) => {
    if (!rest.multiSelectItems) return
    if (selected[0] !== firstSelectedMultiselectItem) {
      setShowErrorDialog(true)
    } else {
      rest.selectPanelProps.onSelectedChange?.(selected)
    }
  }

  const renderAnchor = (buttonProps: React.HTMLAttributes<HTMLElement>) => {
    const {children, ...otherProps} = buttonProps
    return (
      <Button trailingAction={TriangleDownIcon} block {...otherProps}>
        {children}
      </Button>
    )
  }

  let selectPanelProps: SelectPanelProps
  if (rest.multiSelectItems) {
    selectPanelProps = {
      ...rest.selectPanelProps,
      selected: rest.selectPanelProps.selected as ActionListItemInput[],
      onSelectedChange,
      renderAnchor,
    }
  }

  return (
    <>
      <Dialog
        title={
          <span className={clsx(styles.title)} id={MOVE_DIALOG_TITLE_ID} {...testIdProps(MOVE_DIALOG_TITLE_ID)}>
            {title ?? (rest.multiSelectItems ? 'Move selected items' : 'Move selected item')}
          </span>
        }
        onClose={() => {
          closeDialog()
          if (!rest.multiSelectItems) {
            announce(DragAndDropResources.cancelMove(singleSelectedItemValue), {assertive: true})
          } else {
            const selectedItems = rest.selectPanelProps.selected as ActionListItemInput[]
            announce(
              DragAndDropResources.cancelMoveMultiple(selectedItems[0]?.text ?? '', selectedItems?.length ?? 0),
              {
                assertive: true,
              },
            )
          }
        }}
        width="large"
        ref={containerRef}
        renderBody={() => (
          // By default there is no way to wrap the footer and body in one element, so we
          // have to custom-render the footer inside the body. Otherwise we can't use `submit`
          // button to submit the form
          <form
            onSubmit={onSubmit}
            {...testIdProps('move-dialog-form')}
            // Stopping blur propagation fixes a bug where the table thinks the cell editor was
            // blurred when it was really an input inside this dialog.
            onBlur={e => e.stopPropagation()}
            className={clsx(styles.form)}
            noValidate
            aria-labelledby={MOVE_DIALOG_TITLE_ID}
          >
            <Dialog.Body className={clsx(styles.dialogBody)}>
              <div className={clsx(styles.dialogTitle)}>
                {rest.multiSelectItems ? (
                  <FormControl required>
                    <FormControl.Label requiredIndicator={false}>Item(s)</FormControl.Label>
                    <SelectPanel {...selectPanelProps} />
                  </FormControl>
                ) : (
                  <>
                    <span className="text-bold pb-1">Item</span>
                    <span>{singleSelectedItemValue}</span>
                  </>
                )}
              </div>
              <MoveDialogForm
                formProps={formProps}
                setHelperText={setHelperText}
                setIsInvalidOption={setIsInvalidOption}
                helperTextId={helperTextId}
              />
              <Flash
                aria-live="assertive"
                variant={isInvalidOption ? 'danger' : 'default'}
                id={helperTextId}
                {...testIdProps('drag-and-drop-move-dialog-flash')}
              >
                {isInvalidOption ? <AlertIcon /> : <InfoIcon />}
                {helperText}
              </Flash>
            </Dialog.Body>
            <Dialog.Footer className="p-2">
              <Button type="submit" variant="primary" {...testIdProps('drag-and-drop-move-dialog-move-item-button')}>
                {submitButtonLabel ?? 'Move'}
              </Button>
            </Dialog.Footer>
          </form>
        )}
        returnFocusRef={returnFocusRef}
      />
      {showErrorDialog && (
        <Dialog
          width="large"
          title="Missing selection"
          onClose={() => {
            if (rest.multiSelectItems) {
              setShowErrorDialog(false)
            }
          }}
        >
          <Dialog.Body className={clsx(styles.dialogBody)}>
            The first item you selected cannot be deselected when performing a move.
          </Dialog.Body>
          <Dialog.Footer className="p-2">
            <Button
              type="submit"
              variant="primary"
              onClick={() => {
                if (rest.multiSelectItems) {
                  setShowErrorDialog(false)
                }
              }}
            >
              I understand
            </Button>
          </Dialog.Footer>
        </Dialog>
      )}
    </>
  )
}
