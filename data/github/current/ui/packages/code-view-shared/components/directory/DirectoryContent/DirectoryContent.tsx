import {useCurrentTree} from '../../../contexts/CurrentTreeContext'
import {useFilesPageInfo} from '../../../contexts/FilesPageInfoContext'
import type {OverviewPayload} from '@github-ui/code-view-types'
import {useCurrentRepository} from '@github-ui/current-repository'
import {parentPath, repositoryTreePath} from '@github-ui/paths'
import {ScreenReaderHeading} from '@github-ui/screen-reader-heading'
// eslint-disable-next-line no-restricted-imports
import {ScreenSize} from '@github-ui/screen-size'
import {useNavigate} from '@github-ui/use-navigate'
import {AlertIcon} from '@primer/octicons-react'
import {Flash, Link, Truncate} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import React from 'react'

import {useFocusHintContext} from '@github-ui/focus-hint-context'
import {useCommitInfo} from '../../../hooks/use-commit-info'
import {useInitiallyTruncatedList} from '../../../hooks/use-initially-truncated-list'
import {useUrlCreator} from '../../../hooks/use-url-creator'
import {LatestCommitContent} from '../../LatestCommit'
import {Dropzone} from './Dropzone'
import {DirectoryRow, GoDirectoryUpRow} from './DirectoryRow'
import {HeaderRow, Row, Table, TableFooter} from './Table'

import styles from './DirectoryContent.module.css'
import {clsx} from 'clsx'

export function DirectoryContent({overview}: {overview?: OverviewPayload}) {
  const repo = useCurrentRepository()
  const {refInfo, path} = useFilesPageInfo()
  const {items, templateDirectorySuggestionUrl, totalCount} = useCurrentTree()
  // When switching to SSR it will probably be best to remove this and
  // render all the items initially.
  const {items: itemsToShow} = useInitiallyTruncatedList(items, 100)
  const [truncateForMobile, setTruncateForMobile] = React.useState(!!overview)
  const omitted = totalCount - items.length
  const {commitInfo} = useCommitInfo()
  // Overview has a path == '/' and we want to hide the parent link in that case
  const isSubdirectory = path.length > 1

  const parentUrl = parentPath(path)
  const parentPathHref = repositoryTreePath({repo, action: 'tree', commitish: refInfo.name, path: parentUrl})
  const uploadUrl = repositoryTreePath({
    repo,
    commitish: refInfo.name,
    path,
    action: 'upload',
  })

  const goToParentLinkRef = React.useRef<HTMLAnchorElement>(null)

  const {getItemUrl} = useUrlCreator()
  const navigate = useNavigate()
  const {focusHint} = useFocusHintContext()

  const [focusedIndex, setFocusedIndex] = React.useState(-1)

  const onNavigate: React.MouseEventHandler<HTMLAnchorElement> = React.useCallback(e => {
    if (e.screenX === 0 && e.screenY === 0) {
      // On keyboard navigation, set focus on the parent row
      goToParentLinkRef.current?.focus()
    }
  }, [])

  const onViewFilesButtonClick = React.useCallback(() => {
    setTruncateForMobile(false)
  }, [])

  const focusNextIndex = React.useCallback((nextIndex: number) => {
    setFocusedIndex(nextIndex)
    const row = document.getElementById(`folder-row-${nextIndex}`)
    let cell
    if (window.innerWidth <= ScreenSize.medium) {
      cell = row?.querySelector('.react-directory-row-name-cell-small-screen')
    } else {
      cell = row?.querySelector('.react-directory-row-name-cell-large-screen')
    }
    // If the cell wasn't found, this should be the GoDirectoryUpRow, so focus the only Link.
    if (!cell) {
      cell = row
    }
    cell?.getElementsByTagName('a')[0]?.focus()
  }, [])

  return (
    <div data-hpc>
      <button
        hidden
        data-testid="focus-next-element-button"
        data-hotkey="j"
        onClick={() => {
          const nextIndex = Math.min(focusedIndex + 1, isSubdirectory ? itemsToShow.length : itemsToShow.length - 1)
          focusNextIndex(nextIndex)
        }}
      />
      <button
        hidden
        data-testid="focus-previous-element-button"
        data-hotkey="k"
        onClick={() => {
          const nextIndex = Math.max(focusedIndex - 1, 0)
          focusNextIndex(nextIndex)
        }}
      />
      <ScreenReaderHeading as="h2" text="Folders and files" id="folders-and-files" />
      <Table aria-labelledby="folders-and-files" className={styles.Table}>
        <HeaderRow className={clsx(overview && styles.OverviewHeaderRow)}>
          <th colSpan={2} className={styles.Box}>
            <span className="text-bold">Name</span>
          </th>
          <th colSpan={1} className={styles.Box_1}>
            <span className="text-bold">Name</span>
          </th>
          <th className="hide-sm">
            <Truncate inline title="Last commit message" className="width-fit">
              <span className="text-bold">Last commit message</span>
            </Truncate>
          </th>
          <th colSpan={1} className={styles.Box_2}>
            <Truncate inline title="Last commit date" className="width-fit">
              <span className="text-bold">Last commit date</span>
            </Truncate>
          </th>
        </HeaderRow>
        <tbody>
          {!!overview && (
            <>
              <tr className={styles.Box_3}>
                <td colSpan={3} className="bgColor-muted p-1 rounded-top-2">
                  <LatestCommitContent commitCount={overview?.commitCount} />
                </td>
              </tr>
              {omitted > 0 ? (
                <tr>
                  <td colSpan={3}>
                    <Flash variant="warning" className="rounded-0">
                      <Octicon icon={AlertIcon} />
                      Sorry, we had to truncate this directory to 1,000 files. {omitted} entries were omitted from the
                      list.
                    </Flash>
                  </td>
                </tr>
              ) : null}
            </>
          )}

          {isSubdirectory && (
            <GoDirectoryUpRow
              initialFocus={!focusHint || !itemsToShow.some(i => i.path === focusHint)}
              linkTo={parentPathHref}
              linkRef={goToParentLinkRef}
              navigate={navigate}
            />
          )}
          {itemsToShow.map((item, index) => (
            <DirectoryRow
              key={item.name}
              initialFocus={item.path === focusHint}
              item={item}
              commit={(commitInfo || {})[item.name]}
              onNavigate={onNavigate}
              getItemUrl={getItemUrl}
              navigate={navigate}
              className={truncateForMobile && index >= 10 ? 'truncate-for-mobile' : undefined}
              index={isSubdirectory ? index + 1 : index}
            />
          ))}
          <tr
            className={clsx(truncateForMobile && itemsToShow.length > 10 ? 'show-for-mobile' : 'd-none', styles.Box_4)}
            data-testid="view-all-files-row"
          >
            <td colSpan={3} onClick={onViewFilesButtonClick} className={styles.Box_5}>
              <div>
                <Link as="button" onClick={onViewFilesButtonClick}>
                  View all files
                </Link>
              </div>
            </td>
          </tr>
        </tbody>
        {templateDirectorySuggestionUrl && (
          <TableFooter>
            <Row>
              <td colSpan={3}>
                Customize the issue creation experience with a <code>config.yml</code> file.{' '}
                <Link inline href={templateDirectorySuggestionUrl}>
                  Learn more about configuring a template chooser.
                </Link>
              </td>
            </Row>
          </TableFooter>
        )}
      </Table>
      {repo.currentUserCanPush && <Dropzone uploadUrl={uploadUrl} />}
    </div>
  )
}
