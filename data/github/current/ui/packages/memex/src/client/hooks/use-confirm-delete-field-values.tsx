import {Flash, useConfirm} from '@primer/react'
import {useCallback} from 'react'

import {MemexColumnDataType} from '../api/columns/contracts/memex-column'
import type {ColumnModel} from '../models/column-model'
import {SettingsResources, WorkflowResources} from '../strings'
import styles from './use-confirm-delete-field-values.module.css'
import {useEnabledFeatures} from './use-enabled-features'

interface Args {
  field: ColumnModel
  values: Array<string>
  /** Number of items in the project that this will impact. */
  affectedItems: number
  /** Number of workflows that this will impact. */
  affectedWorkflows: number
}

export const useConfirmDeleteFieldValues = () => {
  const confirm = useConfirm()

  return useCallback(
    async (args: Args) =>
      args.values.length === 0 // no-op; nothing to delete
        ? false
        : confirm({
            title: SettingsResources.deleteValuesTitle(args.field.dataType, args.values.length),
            content: <Content {...args} />,
            confirmButtonContent: 'Delete',
            confirmButtonType: 'danger',
          }),
    [confirm],
  )
}

const Warning = ({children}: {children: React.ReactNode}) => (
  <Flash variant="danger" as="p" className={styles.Flash}>
    <span className="sr-only">Warning: </span>
    {children}
  </Flash>
)

const Content = ({field, values: options, affectedItems, affectedWorkflows}: Args) => {
  const {memex_table_without_limits} = useEnabledFeatures()
  const {intro, itemsWarning, workflowsWarning} = getStringsForContent(
    field,
    options.length,
    affectedItems,
    affectedWorkflows,
    !!memex_table_without_limits,
  )

  return (
    <>
      <p>
        {intro} <strong>{SettingsResources.cannotBeUndone}</strong>
      </p>
      {itemsWarning && <Warning>{itemsWarning}</Warning>}
      {workflowsWarning && <Warning>{workflowsWarning}</Warning>}
    </>
  )
}

function getStringsForContent(
  field: ColumnModel,
  optionsCount: number,
  affectedItems: number,
  affectedWorkflows: number,
  mwlEnabled: boolean,
) {
  const workflowsWarning =
    affectedWorkflows > 0
      ? WorkflowResources.deleteValuesAffectedWorkflowsWarning(field.dataType, optionsCount, affectedWorkflows)
      : null

  if (field.dataType === MemexColumnDataType.Iteration) {
    const intro = SettingsResources.deleteIterationValuesIntro(field.name, optionsCount)
    const itemsWarning = getDeleteIterateValuesWarning(affectedItems, optionsCount, mwlEnabled)
    return {intro, workflowsWarning, itemsWarning}
  } else {
    const intro = SettingsResources.deleteValuesIntro(field.dataType, field.name, optionsCount)
    const itemsWarning = getDeleteFieldValuesWarning(field, affectedItems, optionsCount, mwlEnabled)
    return {intro, workflowsWarning, itemsWarning}
  }
}

function getDeleteIterateValuesWarning(affectedItems: number, optionsCount: number, mwlEnabled: boolean) {
  if (affectedItems > 0) {
    return SettingsResources.deleteIterationValuesAffectedItemsWarning(optionsCount, affectedItems)
  } else if (mwlEnabled) {
    return SettingsResources.deleteIterationValuesUnknownAffectedItemsWarning(optionsCount)
  }
  return null
}

function getDeleteFieldValuesWarning(
  field: ColumnModel,
  affectedItems: number,
  optionsCount: number,
  mwlEnabled: boolean,
) {
  if (affectedItems > 0) {
    return SettingsResources.deleteValuesAffectedItemsWarning(field.dataType, optionsCount, affectedItems)
  } else if (mwlEnabled) {
    return SettingsResources.deleteValuesUnknownAffectedItemsWarning(field.dataType, optionsCount)
  }
  return null
}
