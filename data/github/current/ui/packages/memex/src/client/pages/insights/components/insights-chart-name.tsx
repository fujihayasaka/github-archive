import {testIdProps} from '@github-ui/test-id-props'
import {PencilIcon} from '@primer/octicons-react'
import {Button, FormControl, Heading, IconButton, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {memo, type RefObject, useCallback, useRef, useState} from 'react'
import type {SpaceProps, TypographyProps} from 'styled-system'

import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import type {ChartState} from '../../../state-providers/charts/use-charts'
import {useInsightsChartName} from '../hooks/use-insights-chart-name'
import styles from './insights-chart-name.module.css'

interface InsightsChartNameProps {
  chart: ChartState
}

export const InsightsChartName = memo(function InsightsChartName({
  chart,
}: TypographyProps & SpaceProps & InsightsChartNameProps) {
  const {hasWritePermissions} = ViewerPrivileges()
  const {chartName} = useInsightsChartName(chart)

  const [isEditingName, setIsEditingName] = useState(false)
  const editButtonRef = useRef<HTMLButtonElement>(null)

  return (
    <>
      <div className={styles.Box}>
        <div className={styles.Box_1}>
          <div className={styles.Box_2} {...testIdProps('insights-chart-name')}>
            {chartName}
          </div>
          {hasWritePermissions && (
            <IconButton
              ref={editButtonRef}
              icon={PencilIcon}
              onClick={() => setIsEditingName(true)}
              variant="invisible"
              aria-label="Edit chart name"
              {...testIdProps('chart-name-edit-button')}
            />
          )}
        </div>
      </div>
      <ChartNameEditorDialog
        chart={chart}
        isOpen={isEditingName}
        setIsOpen={setIsEditingName}
        returnFocusRef={editButtonRef}
      />
    </>
  )
})

const ChartNameEditorDialog = ({
  chart,
  isOpen,
  setIsOpen,
  returnFocusRef,
}: {
  chart: ChartState
  isOpen: boolean
  setIsOpen: React.Dispatch<boolean>
  returnFocusRef: RefObject<HTMLButtonElement>
}) => {
  const {chartName, setLocalChartName, revertChartName, saveChartName} = useInsightsChartName(chart)
  const inputRef = useRef<HTMLInputElement>(null)
  const onChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => setLocalChartName(event.target.value),
    [setLocalChartName],
  )

  const handleNameChange = useCallback(() => {
    setIsOpen(false)
    saveChartName()
  }, [saveChartName, setIsOpen])

  const closeDialog = useCallback(() => {
    revertChartName()
    setIsOpen(false)
  }, [revertChartName, setIsOpen])

  return (
    <Dialog
      isOpen={isOpen}
      initialFocusRef={inputRef}
      returnFocusRef={returnFocusRef}
      onDismiss={closeDialog}
      aria-labelledby="chart-name-editor-header"
      key={isOpen ? 'open' : 'closed'}
    >
      <Dialog.Header id="chart-name-editor-header" className={styles.Dialog_Header}>
        <Heading as="h3" className={styles.Heading}>
          Edit chart name
        </Heading>
      </Dialog.Header>
      <div className={styles.Box_3}>
        <FormControl className={styles.FormControl}>
          <FormControl.Label>Chart name</FormControl.Label>
          <TextInput
            ref={inputRef}
            name="chartName"
            value={chartName}
            onChange={onChange}
            className={styles.TextInput}
            {...testIdProps('chart-name-editor-input')}
          />
        </FormControl>
      </div>
      <div className={styles.Box_4}>
        <Button variant="default" onClick={closeDialog}>
          Cancel
        </Button>
        <Button variant="primary" onClick={handleNameChange}>
          Save
        </Button>
      </div>
    </Dialog>
  )
}
