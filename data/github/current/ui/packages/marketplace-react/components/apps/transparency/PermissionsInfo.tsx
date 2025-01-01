import {DataTable} from '@primer/react/experimental'
import {Text, Stack} from '@primer/react'
import {joinWords} from '../../../utilities/join-words'
import {capitalize} from '../../../utilities/capitalize'
import React from 'react'
import type {PermissionsData} from '../../../types'

type TableRowData = {
  scope: string
  permissionLevel: string
  values: string[]
  id: string
}

export function PermissionsInfo({permissionsData}: {permissionsData: PermissionsData[]}) {
  const hasRepositoryPermissions = permissionsData.some(permission => permission.scope === 'repository')

  const data: TableRowData[] = []
  for (const row of permissionsData) {
    const {scope, permissionLevel, values} = row
    data.push({
      scope,
      permissionLevel,
      values,
      id: `${scope}-${permissionLevel}`,
    })
  }
  data.push({
    scope: 'user',
    permissionLevel: 'read',
    values: ['public repositories', 'public organization information', 'public user profile data'],
    id: 'public-read',
  })

  return (
    <Stack gap="condensed" data-testid="permissions-info">
      <DataTable
        data={data}
        columns={[
          {
            header: 'Scope',
            id: 'scope',
            renderCell: row => {
              return (
                <Text size="small" weight="semibold">
                  {row.scope === 'single file' ? 'Repository' : capitalize(row.scope)}
                </Text>
              )
            },
          },
          {
            header: 'Description',
            id: 'description',
            renderCell: row => {
              return (
                <>
                  {row.permissionLevel === 'read' ? (
                    <Text weight="semibold">Read</Text>
                  ) : row.permissionLevel === 'write' ? (
                    <>
                      <Text weight="semibold">Read</Text>&nbsp;and&nbsp;<Text weight="semibold">write</Text>
                    </>
                  ) : (
                    <Text weight="semibold">Admin</Text>
                  )}
                  {row.scope === 'single file' ? (
                    <>
                      &nbsp;access to files located at&nbsp;
                      {row.values.map((value, index) => (
                        <React.Fragment key={value}>
                          <code>{value}</code>
                          {index < row.values.length - 1 && <>,&nbsp;</>}
                        </React.Fragment>
                      ))}
                    </>
                  ) : (
                    <>&nbsp;access to {joinWords(row.values)}</>
                  )}
                </>
              )
            },
          },
        ]}
      />
      {hasRepositoryPermissions && (
        <Text size="small" className="fgColor-muted">
          Repository permissions can be granted for all or selected repositories owned by the installing account.
        </Text>
      )}
    </Stack>
  )
}
