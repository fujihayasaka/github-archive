import {testIdProps} from '@github-ui/test-id-props'
import {StopIcon} from '@primer/octicons-react'
import {Button, FormControl, Heading, TextInput} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {memo, useCallback, useMemo, useState} from 'react'
import {useParams} from 'react-router-dom'

import {MemexColumnDataType} from '../../../api/columns/contracts/memex-column'
import {SettingsFieldRename, SettingsFieldRenameSettingsUI} from '../../../api/stats/contracts'
import {getColumnIcon, getColumnText} from '../../../components/column-detail-helpers'
import {Blankslate} from '../../../components/common/blankslate'
import {EmojiAutocomplete} from '../../../components/common/emoji-autocomplete'
import {errorStyle} from '../../../components/common/state-style-decorators'
import {SingleSelectOptions} from '../../../components/fields/single-select/single-select-options'
import {getColumnWarning} from '../../../helpers/get-column-warning'
import {isColumnUserEditable} from '../../../helpers/is-column-editable'
import {not_typesafe_nonNullAssertion} from '../../../helpers/non-null-assertion'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import {useAutosave} from '../../../hooks/use-autosave'
import type {ColumnModel} from '../../../models/column-model'
import {useNavigate} from '../../../router'
import {useProjectRouteParams} from '../../../router/use-project-route-params'
import {PROJECT_SETTINGS_FIELD_ROUTE} from '../../../routes'
import {useAllColumns} from '../../../state-providers/columns/use-all-columns'
import {useSetColumnName} from '../../../state-providers/columns/use-set-column-name'
import {useCustomFieldsSettings} from '../../../state-providers/settings/use-custom-fields-settings'
import {Resources} from '../../../strings'
import {CONTENT_WIDTH} from '../constants'
import {ColumnSettingsBanner} from './column-settings-banner'
import styles from './column-settings-view.module.css'
import {DeleteFieldDialog} from './delete-field-dialog'
import {IterationConfigurationView} from './iteration-configuration-view'
import {ProgressConfigurationView} from './progress-configuration-view'

export const ColumnSettingsView: React.FC = () => {
  const {allColumns} = useAllColumns()
  const {fieldId} = useParams<'fieldId'>()
  const navigate = useNavigate()
  const projectRouteParams = useProjectRouteParams()
  const userEditableColumns = useMemo(() => {
    return allColumns.filter(column => {
      return isColumnUserEditable(column)
    })
  }, [allColumns])

  const column = useMemo(
    () => (fieldId !== undefined ? userEditableColumns.find(c => `${c.id}` === fieldId) : undefined),
    [userEditableColumns, fieldId],
  )

  const headingName = `${column?.name} field settings`

  const {setCurrentColumnTitle} = useCustomFieldsSettings()
  setCurrentColumnTitle(headingName)

  const {postStats} = usePostStats()
  const {updateName} = useSetColumnName()

  const onUpdateColumnName = useCallback(
    async (name: string) => {
      if (!column) return
      if (name === column.name) return

      await updateName(column, name)

      postStats({
        name: SettingsFieldRename,
        ui: SettingsFieldRenameSettingsUI,
        context: `new name: ${name}, original name: ${column.name}`,
        memexProjectColumnId: column.id,
      })
    },
    [column, postStats, updateName],
  )

  const {localValue, isError, isSuccess, inputProps} = useAutosave({
    initialValue: column?.name ?? '',
    commitFn: onUpdateColumnName,
  })

  if (!column) {
    return <NoFieldFound />
  }

  const Icon = getColumnIcon(column.dataType)
  const columnWarning = getColumnWarning(column)

  return (
    <div className={styles.Box} {...testIdProps(`column-settings-${column.name}`)}>
      {columnWarning && <ColumnSettingsBanner warning={columnWarning} column={column} />}
      <div className={styles.Box_1}>
        <Heading as="h2" className={styles.Heading}>
          {headingName}
        </Heading>
        {column.userDefined ? (
          <DeleteField
            column={column}
            numberOfColumns={userEditableColumns.length}
            onDeleteColumn={() => {
              const index = userEditableColumns.findIndex(col => col.id === column.id)

              navigate(
                PROJECT_SETTINGS_FIELD_ROUTE.generatePath({
                  ...projectRouteParams,
                  fieldId: not_typesafe_nonNullAssertion(userEditableColumns[Math.max(0, index - 1)]).id,
                }),
                {replace: true},
              )
            }}
          />
        ) : null}
      </div>
      <div className={styles.Box_2}>
        <FormControl>
          <FormControl.Label>Field name</FormControl.Label>

          {column.userDefined ? (
            <EmojiAutocomplete>
              {/* NOTE: The error styles are passed in manually here, but FormControl automatically
                    supplies this when an error validation is visible. For some reason, the InlineAutocomplete
                    component interrupts this and stops it from working. */}
              <TextInput
                key={column.id}
                value={localValue}
                {...inputProps}
                sx={{width: CONTENT_WIDTH, ...(isError ? errorStyle : {})}}
              />
            </EmojiAutocomplete>
          ) : (
            <TextInput sx={{width: CONTENT_WIDTH}} disabled value={column.name} />
          )}
          {!column.userDefined && (
            <FormControl.Caption>{column.name} fields are created by GitHub and cannot be renamed.</FormControl.Caption>
          )}
          {isError && (
            <FormControl.Validation variant="error">
              {localValue.length === 0 ? Resources.requiredFieldErrorMessage : Resources.genericErrorMessage}
            </FormControl.Validation>
          )}
          {isSuccess && <FormControl.Validation variant="success">Saved!</FormControl.Validation>}
        </FormControl>
      </div>
      <div>
        <div className={styles.Box_3}>Field type</div>
        <Button leadingVisual={Icon} disabled>
          {getColumnText(column.dataType)}
        </Button>
      </div>
      <ConfigurationOptions column={column} />
    </div>
  )
}

const DeleteField = ({
  column,
  numberOfColumns,
  onDeleteColumn,
}: {
  column: ColumnModel
  numberOfColumns: number
  onDeleteColumn: () => void
}) => {
  const [isDialogOpen, setIsDialogOpen] = useState(false)

  return (
    <>
      <Button variant="danger" onClick={() => setIsDialogOpen(true)}>
        Delete field
      </Button>
      <DeleteFieldDialog
        numberOfColumns={numberOfColumns}
        columnModel={column}
        isDialogOpen={isDialogOpen}
        setIsDialogOpen={setIsDialogOpen}
        onDeleteColumn={onDeleteColumn}
      />
    </>
  )
}

const ConfigurationOptions: React.FC<{column: ColumnModel}> = memo(function ConfigurationOptions({column}) {
  switch (column.dataType) {
    case MemexColumnDataType.Iteration: {
      return <IterationConfigurationView column={column} />
    }
    case MemexColumnDataType.SingleSelect: {
      return <SingleSelectOptions column={column} />
    }
    case MemexColumnDataType.SubIssuesProgress: {
      return <ProgressConfigurationView column={column} />
    }
    default: {
      return null
    }
  }
})

const NoFieldFound = memo(function NoFieldFound() {
  return (
    <Blankslate
      sx={{
        backgroundColor: theme => `${theme.colors.canvas.default}`,
      }}
      className={styles.Blankslate}
    >
      <Octicon icon={StopIcon} size={30} className={styles.Octicon} />
      <h2>This field no longer exists</h2>
      <p className={styles.Text}>Select another field to view settings.</p>
    </Blankslate>
  )
})
