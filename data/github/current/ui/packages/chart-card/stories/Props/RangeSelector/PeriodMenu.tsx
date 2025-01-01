import {ActionMenu, ActionList, FormControl, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useCallback, useContext, useEffect, useRef, useState} from 'react'
import {DateContext} from './DateContext'
import {toYYYYMMDD} from '../../../ChartCard/toYYYYMMDD'

import styles from './PeriodMenu.module.css'

/**
 * Returns a date (in milliseconds since the epoch) a specified number of months before the current date.
 */
function getDateMonthsAgo(monthsAgo: number): number {
  return new Date().setMonth(new Date().getMonth() - monthsAgo)
}

const periodOptions: {
  [key: string]: {text: string; from?: number; to?: number}
} = {
  all: {text: 'All'},
  lastMonth: {text: 'Last month', from: getDateMonthsAgo(1)},
  last3Months: {text: 'Last 3 months', from: getDateMonthsAgo(3)},
  last6Months: {text: 'Last 6 months', from: getDateMonthsAgo(6)},
  last12Months: {text: 'Last 12 months', from: getDateMonthsAgo(12)},
  last24Months: {text: 'Last 24 months', from: getDateMonthsAgo(24)},
  customRange: {text: 'Custom range'},
}

export function PeriodMenu() {
  /** Prepare the menu’s variables */
  const [selectedPeriod, setSelectedPeriod] = useState<keyof typeof periodOptions>()
  const {from, to, setDate} = useContext(DateContext)

  // When dates change, updated the selected option
  useEffect(() => {
    // Limitation: If you use the custom range dialog to set the earliest possible start date and the latest possible end date,
    // this logic, as written, won’t recognize that as “All”.
    const newSelectedPeriod =
      Object.entries(periodOptions).find(
        ([, {from: optionFrom, to: optionTo}]) =>
          toYYYYMMDD(optionFrom) === toYYYYMMDD(from) && toYYYYMMDD(optionTo) === toYYYYMMDD(to),
      )?.[0] || 'customRange'
    setSelectedPeriod(newSelectedPeriod)
  }, [from, to])

  /** Prepare the dialog’s variables */
  const menuButtonRef = useRef<HTMLButtonElement>(null)
  const fromRef = useRef<HTMLInputElement>(null)
  const toRef = useRef<HTMLInputElement>(null)
  const [dialogOpen, setDialogOpen] = useState<boolean | undefined>()

  /** Show the dialog containing the data table */
  const openDialog = useCallback(() => setDialogOpen(true), [])

  /** Hide the dialog containing the data table. */
  const closeDialog = useCallback(() => setDialogOpen(false), [])

  /** After dialog is hidden, return focus to the menu button. */
  useEffect(() => {
    if (dialogOpen === false) {
      menuButtonRef.current?.focus()
    }
  }, [dialogOpen])

  return (
    <>
      <ActionMenu>
        <ActionMenu.Button ref={menuButtonRef}>
          {`Period: ${selectedPeriod ? periodOptions[selectedPeriod]?.text : ''}`}
        </ActionMenu.Button>
        <ActionMenu.Overlay>
          <ActionList>
            {Object.entries(periodOptions)
              .filter(([key]) => key !== 'customRange')
              .map(([key, {text, from: optionFrom, to: optionTo}]) => (
                <ActionList.Item
                  key={key}
                  onSelect={() => {
                    // Note that it’s _not_ necessary to call `setSelectedPeriod` here;
                    // the effect above will call it in response to `from` and `to` changing.
                    setDate({from: optionFrom, to: optionTo})
                  }}
                >
                  {text}
                </ActionList.Item>
              ))}
            <ActionList.Divider />
            <ActionList.Item onSelect={openDialog}>Custom range</ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {dialogOpen && (
        // Limitation: Currently, unless the “Apply” button is focused, pressing “Enter” does not submit the form.
        <Dialog
          title="Custom range"
          onClose={closeDialog}
          width="small"
          footerButtons={[
            {
              buttonType: 'default',
              content: 'Apply',
              onClick: () => {
                setDate({
                  from: fromRef.current?.value ? Date.parse(fromRef.current?.value) : undefined,
                  to: toRef.current?.value ? Date.parse(toRef.current?.value) : undefined,
                })
                closeDialog()
              },
            },
          ]}
        >
          <FormControl required className={styles.PeriodMenuFormControl}>
            <FormControl.Label>From</FormControl.Label>
            {/* Apparently `<input type="date">`’s take a YYYY-MM-DD string as their value. TIL. */}
            <TextInput type="date" defaultValue={toYYYYMMDD(from)} ref={fromRef} />
          </FormControl>
          <FormControl>
            <FormControl.Label>To</FormControl.Label>
            <TextInput type="date" defaultValue={toYYYYMMDD(to)} ref={toRef} />
          </FormControl>
        </Dialog>
      )}
    </>
  )
}
