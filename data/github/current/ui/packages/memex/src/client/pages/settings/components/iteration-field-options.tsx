import {announce} from '@github-ui/aria-live'
import {testIdProps} from '@github-ui/test-id-props'
import {Button, Flash} from '@primer/react'
import {Fragment, useEffect, useMemo, useRef} from 'react'

import type {IterationConfiguration} from '../../../api/columns/contracts/iteration'
import {ColumnSettingsSavedMessage} from '../../../components/column-settings-saved-message'
import {RequestStateIcon} from '../../../components/common/state-style-decorators'
import {not_typesafe_nonNullAssertion} from '../../../helpers/non-null-assertion'
import {usePrefixedId} from '../../../hooks/common/use-prefixed-id'
import {useIterationFieldOptions} from '../../../hooks/use-iteration-field-options'
import type {ColumnModel} from '../../../models/column-model'
import {useProjectDetails} from '../../../state-providers/memex/use-project-details'
import {Resources, SettingsResources} from '../../../strings'
import {AddBreakButton} from './iteration/add-break-button'
import {IterationBreakRow} from './iteration/iteration-break-row'
import {IterationRow} from './iteration/iteration-row'
import {IterationsHeader} from './iteration/iterations-header'
import styles from './iteration-field-options.module.css'
import {NoIterationsPlaceholder} from './no-iterations-placeholder'

type IterationFieldOptionsProps = {
  column: ColumnModel
  /**
   * Name of field, to use when generating new iterations
   */
  fieldName: string
  /**
   * The server-side configuration state.
   */
  serverConfiguration: IterationConfiguration
  /**
   * The callback to invoke with changes to the configuration for this field
   */
  onUpdate: (changes: Partial<IterationConfiguration>) => Promise<void>
}

export function IterationFieldOptions({column, fieldName, serverConfiguration, onUpdate}: IterationFieldOptionsProps) {
  const {
    // data
    allRowData,
    // checks
    areColumnValuesLoaded,
    hasUnsavedChanges,
    isActiveTab,
    // selected tab
    selectedTab,
    setSelectedTab,
    // handlers
    handleRemoveIteration,
    handleCreateIteration,
    handleChangeIteration,
    handleAddBreak,
    handleChangeBreak,
    handleReset,
    handleSaveChanges,
    countPushedActiveIterations,
    // configurations
    localConfiguration,
    minimumStartDate,
    defaultDuration,
    requestStatus,
  } = useIterationFieldOptions({
    column,
    fieldName,
    serverConfiguration,
    onUpdate,
  })

  const newIterationRowRef = useRef<HTMLDivElement | null>(null)
  const iterationsLength = localConfiguration.iterations.length
  const lastIterationsLength = useRef(iterationsLength)
  const completedIterationsLength = localConfiguration.completedIterations.length
  const lastCompletedIterationsLength = useRef(completedIterationsLength)
  const {title} = useProjectDetails()

  useEffect(() => {
    if (!newIterationRowRef.current) return
    // Iterations containers did not expand
    if (
      iterationsLength <= lastIterationsLength.current &&
      completedIterationsLength <= lastCompletedIterationsLength.current
    )
      return
    newIterationRowRef.current.scrollIntoView({behavior: 'smooth'})
  }, [iterationsLength, completedIterationsLength])

  useEffect(() => {
    lastIterationsLength.current = iterationsLength
    lastCompletedIterationsLength.current = completedIterationsLength
  })

  // Announce the success or failure of the save operation to screen readers
  useEffect(() => {
    // eslint-disable-next-line i18n-text/no-en
    if (requestStatus === 'succeeded') announce(`Changes saved. Return to ${title}.`)
    if (requestStatus === 'failed') announce(Resources.genericErrorMessage)
  }, [requestStatus, title])

  const rows = useMemo(
    () =>
      allRowData
        .filter(({originalIsCompleted}) => (selectedTab === 'completed' ? originalIsCompleted : !originalIsCompleted))
        .map(
          (
            {
              localIteration,
              localPreviousIteration,
              originalIteration,
              originalIsCompleted,
              originalPreviousIteration,
              breakExistsBefore,
            },
            index,
          ) => {
            return (
              <Fragment key={localIteration.id}>
                {breakExistsBefore ? (
                  <IterationBreakRow
                    onChange={interval =>
                      handleChangeBreak(not_typesafe_nonNullAssertion(localPreviousIteration), localIteration, interval)
                    }
                    localNextIteration={localIteration}
                    localPreviousIteration={not_typesafe_nonNullAssertion(localPreviousIteration)}
                    originalNextIteration={originalIteration}
                    originalPreviousIteration={originalPreviousIteration}
                  />
                ) : null}
                <IterationRow
                  iteration={localIteration}
                  originalIsCompleted={originalIsCompleted}
                  onRemove={() => handleRemoveIteration(localIteration)}
                  onChange={handleChangeIteration}
                  previousIteration={localPreviousIteration}
                  originalIteration={originalIteration}
                >
                  {breakExistsBefore ? null : (
                    <AddBreakButton onClick={() => handleAddBreak(localIteration)} removeTopPadding={index === 0} />
                  )}
                </IterationRow>
              </Fragment>
            )
          },
        ),
    [allRowData, selectedTab, handleAddBreak, handleChangeIteration, handleRemoveIteration, handleChangeBreak],
  )

  const tabpanelId = usePrefixedId('iteration-field-options')

  const saveChangesDisabled = !hasUnsavedChanges || requestStatus === 'loading' || !areColumnValuesLoaded
  const resetChangesDisabled = !hasUnsavedChanges || requestStatus === 'loading'

  return (
    <>
      <div className={styles.Box}>
        <IterationsHeader
          configuration={localConfiguration}
          selectedTab={selectedTab}
          setSelectedTab={setSelectedTab}
          addButtonProps={{minimumStartDate, defaultDuration, onCreate: handleCreateIteration}}
          disabled={hasUnsavedChanges}
          tabpanelId={tabpanelId}
        />
        <div role="tabpanel" id={tabpanelId}>
          {rows.length > 0 ? (
            <ol
              aria-label={selectedTab === 'completed' ? 'Completed iterations' : 'Active iterations'}
              className={styles.Box_1}
            >
              {rows}
            </ol>
          ) : (
            <NoIterationsPlaceholder isActiveTab={isActiveTab} />
          )}
        </div>
        {selectedTab === 'completed' && countPushedActiveIterations > 0 && (
          <Flash className={styles.Flash} {...testIdProps('active-changes-notice')}>
            {SettingsResources.willPushActiveIterations(countPushedActiveIterations)}
          </Flash>
        )}
      </div>
      <div ref={newIterationRowRef} />
      <div className={styles.Box_2}>
        <Button
          variant="primary"
          disabled={saveChangesDisabled}
          onClick={() => handleSaveChanges()}
          {...testIdProps('iteration-field-settings-save')}
        >
          {Resources.saveChanges}
        </Button>
        <Button
          disabled={resetChangesDisabled}
          onClick={() => handleReset()}
          {...testIdProps('iteration-field-settings-reset')}
        >
          {Resources.reset}
        </Button>

        <div className={styles.Box_3}>
          <RequestStateIcon status={requestStatus} />
          {requestStatus === 'succeeded' ? (
            <ColumnSettingsSavedMessage title={title} />
          ) : requestStatus === 'failed' ? (
            <span className={styles.Text}>{Resources.genericErrorMessage}</span>
          ) : null}
        </div>
      </div>
    </>
  )
}
