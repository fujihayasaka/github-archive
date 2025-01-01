import {PencilIcon, LockIcon, TrashIcon} from '@primer/octicons-react'
import {DataTable, Table, createColumnHelper} from '@primer/react/experimental'
import {IconButton, Link, RelativeTime, Text, Truncate} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {useMemo, useState} from 'react'
import {FormDialog} from './FormDialog'
import {DeleteDialog} from './DeleteDialog'
import {DescriptionElement} from './DescriptionElement'
import {TableBlankstate} from './ActionsSecretsVariablesBlankstate'
import {TableAction} from './TableAction'

// eslint-disable-next-line import/no-nodejs-modules
import {Buffer} from 'buffer'
import capitalize from 'lodash-es/capitalize'
import {ListMode, ItemsScope, FormMode} from './types'
import type {CrudUrls, ActionsSecretsVariablesListProps, Item, RowData} from './types'

const VISIBILITY_COL_MAX_WIDTH = 180
const LAST_UPDATED_COL_MAX_WIDTH = 127

export function ActionsSecretsVariablesList({
  items,
  overrides,
  scope,
  environmentUrls,
  crudUrls,
  tableActionProps,
  mode,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  description = {text: '', contextUrl: ''},
  isPrivateRepoInFreeOrg = false,
  hideName = false,
  initialSortColumn = 'name',
}: ActionsSecretsVariablesListProps) {
  const lowerCaseScope = scope.toLowerCase()
  const isEditableInScope = crudUrls !== undefined
  const tableName = `${scope} ${mode}s`

  const columnHelper = createColumnHelper<RowData>()
  const columns = []

  const [deleteDialogStates, setDeleteDialogStates] = useState(() => new Map<string, boolean>())
  const [saveDialogStates, setSaveDialogStates] = useState(() => new Map<string, boolean>())
  const [itemsState, setItemsState] = useState(items)
  const [crudUrlsState, setCrudUrlsState] = useState(crudUrls)

  function setIsDeleteDialogOpenForRow(open: boolean, rowId: string) {
    const updatedDialogStates = new Map(deleteDialogStates)
    updatedDialogStates.set(rowId, open)
    setDeleteDialogStates(updatedDialogStates)
  }

  function setIsSaveDialogOpenForRow(open: boolean, rowId: string) {
    const updatedDialogStates = new Map(saveDialogStates)
    updatedDialogStates.set(rowId, open)
    setSaveDialogStates(updatedDialogStates)
  }

  function handleUpdateTableData(item: Item, url: string, formMode: FormMode) {
    if (!item) {
      return
    }

    // Add item or update existing item
    if (formMode === FormMode.add) {
      setItemsState(currentItems => [...currentItems, item])
    } else {
      const index = itemsState.findIndex(i => i.name === item.name)
      if (index !== -1) {
        const newItems = [...itemsState]
        newItems[index] = item
        setItemsState(newItems)
      }
    }

    // Update crudUrls
    const newCrudUrls = crudUrlsState
    if (newCrudUrls?.editUrls) {
      // eslint-disable-next-line react-hooks/react-compiler
      newCrudUrls.editUrls[item.name] = url
    }
    if (newCrudUrls?.deleteUrls) {
      newCrudUrls.deleteUrls[item.name] = url
    }
    setCrudUrlsState(newCrudUrls)
  }

  function handleDeleteTableData(itemName: string) {
    setItemsState(currentItems => currentItems.filter(i => i.name !== itemName))
  }

  const tableAction = (
    <TableAction
      url={tableActionProps.url}
      mode={mode}
      message={tableActionProps.message}
      useDialog={tableActionProps.useDialog}
      isEditableInScope={isEditableInScope}
      publicKey={tableActionProps.publicKey}
      keyId={tableActionProps.keyId}
      tableDataUpdater={handleUpdateTableData}
    />
  )

  // Construct a new array of data with all the items
  const tableData = useMemo(
    () => generateRowData(itemsState, scope, overrides, crudUrls, mode, isEditableInScope, environmentUrls),
    [crudUrls, environmentUrls, isEditableInScope, itemsState, mode, overrides, scope],
  )

  if (tableData.length > 0 && !isPrivateRepoInFreeOrg) {
    // Name column
    if (!hideName) {
      columns.push(
        columnHelper.column({
          id: 'name',
          header: 'Name',
          field: 'id',
          sortBy: 'alphanumeric',
          width: 'growCollapse',
          renderCell: row => {
            let overrideMessage = ''
            if (row.override && scope === ItemsScope.Organization) {
              overrideMessage = `This ${mode} is overridden by a repository ${mode}`
            } else if (row.override && scope === ItemsScope.Repository) {
              overrideMessage = `This ${mode} overrides an organization ${mode}`
            }
            if (overrideMessage === '') {
              return (
                <Truncate inline title={row.id} sx={{maxWidth: '100%'}}>
                  <Octicon icon={LockIcon} className="mr-2" />
                  <code data-testid={`${row.id}-name`}>{row.name}</code>
                </Truncate>
              )
            } else {
              return (
                <Truncate inline title={row.id} className="d-flex flex-items-center" sx={{maxWidth: '100%'}}>
                  <Octicon icon={LockIcon} className="mr-2" />
                  <Truncate inline title={row.id} sx={{maxWidth: '100%'}}>
                    <div className="d-flex flex-column">
                      <Truncate inline title={row.id} sx={{maxWidth: '100%'}}>
                        <code data-testid={`${row.id}-name`}>{row.name}</code>
                      </Truncate>
                      <Truncate inline title={overrideMessage} sx={{maxWidth: '100%', color: 'attention.fg'}}>
                        <Text sx={{color: 'attention.fg'}}>{overrideMessage}</Text>
                      </Truncate>
                    </div>
                  </Truncate>
                </Truncate>
              )
            }
          },
        }),
      )
    }

    // Private registry columns
    if (scope === ItemsScope.OrgPrivateRegistry) {
      // Registry Type column
      columns.push(
        columnHelper.column({
          id: 'type',
          header: 'Type',
          field: 'registryType',
          sortBy: 'alphanumeric',
          width: 'growCollapse',
          renderCell: row => {
            if (row.registryType) {
              return (
                <Truncate inline title={row.registryType} sx={{maxWidth: '100%'}}>
                  <Octicon icon={LockIcon} className="mr-2" />
                  <code data-testid={`${row.id}-registry-type`}>{row.registryType}</code>
                </Truncate>
              )
            }
          },
        }),
      )

      // URL column
      columns.push(
        columnHelper.column({
          id: 'url',
          header: 'URL',
          field: 'registryUrl',
          sortBy: 'alphanumeric',
          width: 'growCollapse',
          renderCell: row => {
            if (row.registryUrl) {
              return (
                <Truncate inline title={row.registryUrl} sx={{maxWidth: '100%'}}>
                  <code data-testid={`${row.id}-registry-url`}>{row.registryUrl}</code>
                </Truncate>
              )
            }
          },
        }),
      )
    }

    // Variable value column
    if (mode === ListMode.variable) {
      columns.push(
        columnHelper.column({
          header: 'Value',
          field: 'value',
          sortBy: 'alphanumeric',
          width: 'growCollapse',
          renderCell: row => {
            if (row.value) {
              return (
                <Truncate inline title={row.value} sx={{maxWidth: '100%'}}>
                  <Text sx={{fontSize: 0}}>{row.value}</Text>
                </Truncate>
              )
            }
          },
        }),
      )
    }

    // Environment column, only show if we're not on the environment page
    if (scope === ItemsScope.Environment && !tableActionProps?.useDialog) {
      columns.push(
        columnHelper.column({
          header: 'Environment',
          field: 'environment',
          sortBy: 'alphanumeric',
          width: 'growCollapse',
          renderCell: row => {
            if (row.environment && row.environmentUrl) {
              return (
                <Truncate inline title={row.environment} sx={{maxWidth: '100%'}}>
                  <Link href={row.environmentUrl} data-testid={`${row.id}-env-link`}>
                    {row.environment}
                  </Link>
                </Truncate>
              )
            }
            return null
          },
        }),
      )
    }

    // Visibility column
    const hasVisibilityDescription = itemsState.some(i => i.visibility_description)
    if (hasVisibilityDescription) {
      columns.push(
        columnHelper.column({
          header: 'Visibility',
          field: 'visibility',
          width: 'auto',
          sortBy: (a: RowData, b: RowData) => {
            const va = a.visibility!
            const vb = b.visibility!
            // Order "All repos" first, then "Private / Internal", then "N repositories" in descending order
            const isNumberedEntry = (entry: string) => /(\d|,)+ repositor(y|ies)/.test(entry)

            if (isNumberedEntry(va) && isNumberedEntry(vb)) {
              // Match numbers, strip commas, and parse the result
              const numA = parseInt(va.match(/(\d|,)+/)![0].replace(/,/g, ''))
              const numB = parseInt(vb.match(/(\d|,)+/)![0].replace(/,/g, ''))
              return numB - numA
            }

            if (va === 'all repositories') return -1
            if (vb === 'all repositories') return 1
            if (va === 'private and internal repositories') return -1
            if (vb === 'private and internal repositories') return 1

            // Alphabetically works for All/Private in this case
            return va.localeCompare(vb)
          },
          renderCell: row => {
            if (row.visibility) {
              return (
                <Truncate inline title={row.visibility} sx={{maxWidth: VISIBILITY_COL_MAX_WIDTH}}>
                  <Text sx={{fontSize: 0}}>{capitalize(row.visibility)}</Text>
                </Truncate>
              )
            }
            return null
          },
        }),
      )
    }

    // Last updated column
    columns.push(
      columnHelper.column({
        header: () => {
          return (
            <Truncate inline title="Last updated" sx={{maxWidth: LAST_UPDATED_COL_MAX_WIDTH}}>
              Last updated
            </Truncate>
          )
        },
        width: 'auto',
        field: 'lastUpdated',
        align: 'end',
        sortBy: 'datetime',
        renderCell: row => {
          if (row.lastUpdated) {
            const date = new Date(row.lastUpdated)
            return (
              <Truncate inline title={date.toLocaleDateString()} sx={{maxWidth: LAST_UPDATED_COL_MAX_WIDTH}}>
                <RelativeTime date={date} tense="past" data-testid={`${row.id}-relative-time`} />
              </Truncate>
            )
          }
        },
      }),
    )

    // Modify buttons column
    if (crudUrls?.editUrls) {
      columns.push(
        columnHelper.column({
          id: 'actions',
          width: 'auto',
          align: 'end',
          header: () => <span className="sr-only">Actions</span>,
          renderCell: row => {
            const editButton = row.editUrl && (
              <div>
                {tableActionProps && !tableActionProps.useDialog ? (
                  // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
                  <IconButton
                    unsafeDisableTooltip
                    aria-label={`Edit ${row.displayName}`}
                    title={`Edit ${row.displayName}`}
                    icon={PencilIcon}
                    variant="invisible"
                    className="mr-1"
                    data-testid={`${row.id}-edit`}
                    href={row.editUrl}
                    as="a"
                  />
                ) : (
                  // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
                  <IconButton
                    unsafeDisableTooltip
                    aria-label={`Edit ${row.displayName}`}
                    title={`Edit ${row.displayName}`}
                    icon={PencilIcon}
                    variant="invisible"
                    className="mr-1"
                    data-testid={`${row.id}-edit`}
                    onClick={() => {
                      setIsSaveDialogOpenForRow(true, row.id)
                    }}
                  />
                )}

                {saveDialogStates.get(row.id) && (
                  <FormDialog
                    mode={mode}
                    rowId={row.id}
                    onClose={() => setIsSaveDialogOpenForRow(false, row.id)}
                    tableDataUpdater={handleUpdateTableData}
                    formMode={FormMode.update}
                    url={row.editUrl ?? ''}
                    publicKey={tableActionProps?.publicKey}
                    keyId={tableActionProps?.keyId}
                    name={row.name}
                    value={row.value}
                  />
                )}
              </div>
            )
            const additionalFormData: {[key: string]: string} = {}
            if (row.deleteUrl && scope === ItemsScope.CodespaceUser && tableActionProps.keyId) {
              additionalFormData['commit'] = 'Delete'
              additionalFormData['codespaces_user_secret[key_id]'] = tableActionProps.keyId
            }
            const deleteButton = row.deleteUrl && (
              <div>
                {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
                <IconButton
                  unsafeDisableTooltip
                  aria-label={`Delete ${row.displayName}`}
                  title={`Delete ${row.displayName}`}
                  icon={TrashIcon}
                  variant="invisible"
                  data-testid={`${row.id}-delete`}
                  onClick={() => {
                    setIsDeleteDialogOpenForRow(true, row.id)
                  }}
                />
                {deleteDialogStates.get(row.id) && (
                  <DeleteDialog
                    url={row.deleteUrl ?? ''}
                    rowId={row.id}
                    setClose={setIsDeleteDialogOpenForRow}
                    mode={mode}
                    tableDataUpdater={handleDeleteTableData}
                    additionalFormData={additionalFormData}
                  />
                )}
              </div>
            )
            return (
              <div className="d-flex">
                {editButton}
                {deleteButton}
              </div>
            )
          },
        }),
      )
    }
  }

  return (
    <div className="mb-5">
      {itemsState.length > 0 && !isPrivateRepoInFreeOrg ? (
        <Table.Container>
          <Table.Title as="h2" id={`${lowerCaseScope}-${mode}s`}>
            <Text sx={{fontSize: 2, fontWeight: 'bold'}}>{tableName}</Text>
          </Table.Title>
          <Table.Actions>{tableAction}</Table.Actions>
          <Table.Subtitle id={`repository-${mode}s-subtitle`}>
            {description.text ? <DescriptionElement description={description} /> : undefined}
          </Table.Subtitle>
          <DataTable
            aria-labelledby={`${lowerCaseScope}-${mode}s`}
            aria-describedby={`${lowerCaseScope}-${mode}s-subtitle`}
            initialSortColumn={initialSortColumn}
            data={tableData}
            columns={columns}
          />
        </Table.Container>
      ) : (
        <TableBlankstate
          scope={scope}
          mode={mode}
          description={description}
          tableAction={tableAction}
          isEditableInScope={isEditableInScope}
          isPrivateRepoInFreeOrg={isPrivateRepoInFreeOrg}
        />
      )}
    </div>
  )
}

function generateRowData(
  items: Item[],
  scope: ItemsScope,
  overrides: Item[] | undefined,
  crudUrls: CrudUrls | undefined,
  mode: ListMode,
  isEditableInScope: boolean,
  environmentUrls: {[environmentName: string]: string} | undefined,
) {
  const result = new Array<RowData>()
  for (const item of items) {
    const tableRow: RowData = {
      id: getItemId(item),
      name: item.name,
      displayName: getDisplayName(item),
      scope,
      lastUpdated: item.updated_at,
      visibility: item.visibility_description,
      override: overrides && overrides.some(obj => obj.hasOwnProperty('name') && obj.name === item.name),
    }

    if (item.registry_data) {
      tableRow.registryUrl = item.registry_data.url
      tableRow.registryType = item.registry_data.type
    }

    if (crudUrls?.editUrls) {
      tableRow.editUrl = crudUrls.editUrls[item.name]
    }

    if (crudUrls?.deleteUrls) {
      tableRow.deleteUrl = crudUrls.deleteUrls[item.name]
    }

    if (mode === ListMode.variable && item.value) {
      if (scope === ItemsScope.Organization) {
        // Org vars are fetched as base64 encoded on the repo page but not the org page
        if (isEditableInScope) {
          tableRow.value = item.value
        } else {
          tableRow.value = Buffer.from(item.value, 'base64').toString()
        }
      } else {
        tableRow.value = Buffer.from(item.value, 'base64').toString()
      }
    }

    if (item.environment_name && environmentUrls) {
      tableRow.environmentUrl = environmentUrls[item.environment_name]
      tableRow.environment = item.environment_name
    }

    result.push(tableRow)
  }
  return result
}

function getItemId(item: Item) {
  // Append the environment name to environment secrets to ensure uniqueness
  if (item.environment_name) {
    return `${item.name}-${item.environment_name}`
  }

  return item.name
}

function getDisplayName(item: Item) {
  if (item.registry_data) {
    return item.registry_data.type
  }

  return item.name
}
