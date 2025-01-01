import {DatabaseIcon, TableIcon} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback, useEffect, useState} from 'react'

import {type ParsedTableDataType, useDatabaseContext} from '../../../contexts/DatabaseContext'
import {Region, RegionState, useRegionState} from '../../../hooks/use-region-state'
import {PanelBlankslate} from '../PanelBlankslate'
import {Section} from '../Section'
import styles from './DataPanel.module.css'
import {DataObjectDialog} from './DataPanel/DataObjectDialog'

export function DataPanel() {
  const panelState = useRegionState(Region.DATA)
  const readOnly = panelState === RegionState.READ_ONLY

  const {isFetchingData, didErrorFetchingData, fetchAllData} = useDatabaseContext()

  const [currentTable, setCurrentTable] = useState<ParsedTableDataType | undefined>(undefined)
  const {currentData} = useDatabaseContext()

  const handleObjectDialogClose = useCallback(async () => {
    setCurrentTable(undefined)
  }, [])

  // listen to the currentData and update the currentTable if it matches
  useEffect(() => {
    if (currentData && currentTable) {
      const matchingTable = currentData.find(table => table.table === currentTable.table)
      if (matchingTable) {
        setCurrentTable(matchingTable)
      } else {
        setCurrentTable(undefined)
      }
    }
  }, [currentData, currentTable])

  if (didErrorFetchingData) {
    return (
      <Banner
        title="Error fetching data"
        description={'There has been an error fetching data. Please try again later.'}
        variant="critical"
        primaryAction={
          <Button loading={isFetchingData} onClick={fetchAllData}>
            Retry
          </Button>
        }
      />
    )
  }

  if (!isFetchingData && (!currentData || currentData.length === 0)) {
    return (
      <PanelBlankslate
        icon={DatabaseIcon}
        title="No data added yet"
        description="Use the Iterate tab to add data storage to your spark."
      />
    )
  }

  return (
    <>
      <div className="mt-3">
        <Section title="Tables" showTitle={false} readOnly={readOnly} loading={isFetchingData}>
          <ActionList className={styles.actionList}>
            {currentData?.map(table => (
              <ActionList.Item
                className={styles.listItem}
                key={table.table}
                onSelect={() => {
                  setCurrentTable(table)
                }}
              >
                <ActionList.LeadingVisual>
                  <TableIcon />
                </ActionList.LeadingVisual>
                {table.table}
                <ActionList.Description variant="block">{getItemDescription(table)}</ActionList.Description>
              </ActionList.Item>
            ))}
          </ActionList>
        </Section>
      </div>

      {currentTable && (
        <DataObjectDialog onClose={handleObjectDialogClose} currentTable={currentTable} readOnly={readOnly} />
      )}
    </>
  )
}

function getItemDescription(table: ParsedTableDataType): string {
  switch (table.data.type) {
    case 'table':
      return `${table.data.data.length} rows • ${table.data.allKeys.join(', ')}`
    case 'array':
      return `Array with ${table.data.data.length} items`
    case 'object':
      return `Object with ${Object.keys(table.data.data).length} keys`
    default:
      return String(table.data.data)
  }
}
