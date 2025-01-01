import {ActionList, ActionMenu, IconButton, Pagination, Stack, VisuallyHidden} from '@primer/react'
import {AlertIcon, BookIcon, KebabHorizontalIcon, MarkGithubIcon} from '@primer/octicons-react'
import {Blankslate, DataTable, Table, type Column} from '@primer/react/experimental'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {clsx} from 'clsx'
import styles from './LicenseeList.module.css'
import type {Dispatch, SetStateAction} from 'react'
import type {Licensee} from '../types/licensee'

interface LicenseeListProps {
  licensees: Licensee[]
  isError: boolean
  isFetching: boolean
  currentPage: number
  totalPages: number
  onPageChange: Dispatch<SetStateAction<number>>
  onOpenMatchDialog: (licensee: Licensee) => void
  onOpenUnmatchDialog: (licensee: Licensee) => void
}

export function LicenseeList({
  licensees,
  isError,
  isFetching,
  currentPage,
  totalPages,
  onPageChange,
  onOpenMatchDialog,
  onOpenUnmatchDialog,
}: LicenseeListProps) {
  if (isError) {
    return (
      <Blankslate border>
        <Blankslate.Visual>
          <AlertIcon size="medium" className="fgColor-muted" />
        </Blankslate.Visual>
        <Blankslate.Heading>Licensed users cannot be loaded</Blankslate.Heading>
        <Blankslate.Description>
          The licensed user list is currently unavailable due to a system error. Try reloading the page, or if the
          problem persists,{' '}
          <a href="https://support.github.com/contact" style={{textDecoration: 'underline'}}>
            contact support
          </a>
          .
        </Blankslate.Description>
      </Blankslate>
    )
  }

  if (licensees.length === 0 && !isFetching) {
    return (
      <Blankslate border>
        <Blankslate.Visual>
          <BookIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>No licensed users</Blankslate.Heading>
        <Blankslate.Description>No licensed users were found for this enterprise.</Blankslate.Description>
      </Blankslate>
    )
  }

  const columns: Array<Column<Licensee>> = [
    {
      header: 'Name',
      field: 'login',
      renderCell: row => {
        return (
          <Stack direction="horizontal" gap="condensed" className={clsx('f5 fgColor-default', styles.licenseeNameCell)}>
            <GitHubAvatar src={row.avatarUrl} alt={row.login} size={32} />
            <Stack direction="vertical" gap="none">
              <div className={styles.licenseeName}>
                <span className={styles.licenseeUsername}>{row.login}</span>
                {row.fullName && <span className={styles.licenseeFullName}>{row.fullName}</span>}
              </div>
              <div className={styles.licenseeAccessType}>{row.accessType}</div>
            </Stack>
          </Stack>
        )
      },
    },
    {
      header: 'License',
      field: 'license',
      renderCell: row => {
        return (
          <span className="f5 fgColor-default">
            {row.license === 'Visual Studio' ? (
              <img
                width={16}
                height={16}
                alt="VSS"
                className="mr-2"
                src="/images/modules/site/logos/visualstudio2019-logo.svg"
                style={{verticalAlign: 'text-bottom'}}
              />
            ) : (
              <MarkGithubIcon size={16} verticalAlign="text-bottom" className="mr-2 fgColor-muted" />
            )}
            {row.license}
          </span>
        )
      },
    },
    {
      id: 'actions',
      header: () => <VisuallyHidden>Actions</VisuallyHidden>,
      maxWidth: '60px',
      renderCell: row => {
        return (
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton
                aria-label={`Actions: ${row.login}`}
                title={`Actions: ${row.login}`}
                icon={KebabHorizontalIcon}
                variant="invisible"
              />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay width="medium">
              <ActionList>
                {row.license === 'Visual Studio' ? (
                  <ActionList.Item onSelect={() => onOpenUnmatchDialog?.(row)}>
                    Change to GitHub Enterprise license
                  </ActionList.Item>
                ) : (
                  <ActionList.Item onSelect={() => onOpenMatchDialog?.(row)}>
                    Change to Visual Studio license
                  </ActionList.Item>
                )}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        )
      },
    },
  ]

  return (
    <>
      <Table.Container>
        {isFetching ? (
          <Table.Skeleton columns={columns} rows={licensees.length || 3} />
        ) : (
          <DataTable data={licensees} columns={columns} />
        )}
      </Table.Container>
      {!isFetching && totalPages > 1 && (
        <Pagination
          currentPage={currentPage}
          pageCount={totalPages}
          onPageChange={(event, page) => {
            event.preventDefault()
            onPageChange(page)
          }}
        />
      )}
    </>
  )
}
