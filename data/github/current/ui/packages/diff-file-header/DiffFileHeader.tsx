import {clsx} from 'clsx'
import {
  ArrowRightIcon,
  ChevronDownIcon,
  ChevronRightIcon,
  CodeIcon,
  FileIcon,
  FoldIcon,
  UnfoldIcon,
} from '@primer/octicons-react'
import {Link, SegmentedControl} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import type {PatchStatus} from '@github-ui/diff-file-helpers'
import {fileModeChanged} from '@github-ui/diff-file-helpers'
import {DiffStats} from '@github-ui/diffs/DiffStats'
import type {ComponentProps, MouseEvent, ReactNode, RefObject} from 'react'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import styles from './DiffFileHeader.module.css'

function FileName({
  newPath,
  oldPath,
  status,
}: {
  newPath?: string | null
  oldPath?: string | null
  status: PatchStatus
}): JSX.Element {
  const newPathElement = <>&lrm;{newPath}</>
  const oldPathElement = <>&lrm;{oldPath}</>
  if (status === 'RENAMED') {
    return (
      <code>
        {oldPathElement} <ArrowRightIcon /> {newPathElement}
      </code>
    )
  } else if (status === 'DELETED' || status === 'REMOVED') {
    return <code>{oldPathElement}</code>
  } else {
    return <code>{newPathElement}</code>
  }
}

export interface DiffFileHeaderProps {
  /**
   * Optional additional content to render to the left of the file name
   */
  additionalLeftSideContent?: ReactNode
  /**
   * Indicates whether the lines in the file have all been expanded
   */
  areLinesExpanded?: boolean
  /**
   * Indicates whether the "expand all" button should be shown
   */
  canExpandOrCollapseLines?: boolean
  /**
   * CSS class that will be applied to the root header element
   */
  className?: string
  /**
   * Indicates whether the diff should default to rich mode
   */
  defaultToRichDiff?: boolean
  /**
   * Overrides for the diff stats component
   */
  diffStatsProps?: ComponentProps<typeof DiffStats>
  /**
   * Indicates if the file is a binary file that may not be displayed
   */
  isBinary?: boolean
  /**
   * Indicates whether the file is in a collapsed state
   */
  isCollapsed?: boolean
  /**
   * Indicates if the file is a submodule diff
   */
  isSubmodule?: boolean
  /**
   * Indicates whether the diff can be displayed in rich mode
   */
  canToggleRichDiff?: boolean
  /**
   * Count of the number of lines added to the file
   */
  linesAdded: number
  /**
   * Count of the number of lines changed in the file
   */
  linesChanged: number
  /**
   * Count of the number of lines deleted from the file
   */
  linesDeleted: number
  /**
   * The href to use for the file name link
   */
  fileLinkHref?: string
  /**
   * A ref to use for the file name link
   */
  fileLinkRef?: RefObject<HTMLAnchorElement>
  /**
   * The new git mode of the file
   */
  newMode?: number
  /**
   * The new path of the file
   */
  newPath?: string | null
  /**
   * The old git mode of the file
   */
  oldMode?: number
  /**
   * The old path of the file
   */
  oldPath?: string | null
  /**
   * Callback invoked when the user clicks the button to copy the file path
   */
  onCopyPath?: () => void
  /**
   * Callback invoked when the user clicks the header
   */
  onHeaderClick?: (e: MouseEvent<HTMLElement>) => void
  /**
   * Callback invoked when the user clicks the button to toggle the expanded state of all lines
   */
  onToggleExpandAllLines?: () => void
  /**
   * Callback invoked when the user clicks the button to toggle the collapsed state of the file
   */
  onToggleFileCollapsed: (event: React.MouseEvent) => void
  /**
   * Callback invloked when the user clicks the button to toggle the display of the diff between rich and source
   */
  onToggleDiffDisplay?: (rich: boolean) => void
  /**
   * The status of the file
   */
  patchStatus: PatchStatus
  /**
   * The path of the file
   */
  path: string
  /**
   * Optional additional content to render after the file name. This content will be right-aligned.
   */
  rightSideContent?: ReactNode
  /**
   * The size of the diff, in human readable form with units, to show when there is a binary file
   */
  size?: string
}

/**
 * Renders the header of a diff file.
 */
export function DiffFileHeader({
  additionalLeftSideContent,
  areLinesExpanded,
  canExpandOrCollapseLines,
  className,
  diffStatsProps,
  defaultToRichDiff,
  isBinary,
  isSubmodule,
  isCollapsed,
  canToggleRichDiff,
  linesAdded,
  linesChanged,
  linesDeleted,
  fileLinkHref,
  fileLinkRef,
  newMode,
  newPath,
  oldMode,
  oldPath,
  onCopyPath,
  onHeaderClick,
  onToggleDiffDisplay,
  onToggleExpandAllLines,
  onToggleFileCollapsed,
  patchStatus,
  path,
  rightSideContent,
  size,
}: DiffFileHeaderProps) {
  const isNegative = size && size[0] === '-'
  return (
    <div
      className={clsx(
        styles['diff-file-header'],
        isCollapsed ? styles['collapsed'] : '',
        'flex-wrap flex-sm-nowrap',
        className,
      )}
    >
      <button
        onClick={onToggleFileCollapsed}
        className="Button Button--iconOnly Button--invisible flex-shrink-0 flex-order-1"
        aria-label={isCollapsed ? `expand file: ${path}` : `collapse file: ${path}`}
      >
        {isCollapsed ? <ChevronRightIcon /> : <ChevronDownIcon />}
      </button>
      {additionalLeftSideContent}
      <div className="d-flex px-1 flex-items-center overflow-hidden flex-order-2 flex-sm-order-1">
        <h3 className={clsx(styles['file-name'])}>
          <Link className="Link--primary" href={fileLinkHref} onClick={onHeaderClick} ref={fileLinkRef}>
            <FileName newPath={newPath} oldPath={oldPath} status={patchStatus} />
          </Link>
        </h3>
        <CopyToClipboardButton
          className="ml-1 flex-shrink-0"
          textToCopy={newPath ?? oldPath ?? ''}
          ariaLabel="Copy file name to clipboard"
          tooltipProps={{direction: 's'}}
          onCopy={onCopyPath}
        />
        {fileModeChanged(patchStatus, oldMode, newMode) && (
          <div className="p-2">
            <code>{oldMode}</code>
            <ArrowRightIcon className="mx-1" />
            <code>{newMode}</code>
          </div>
        )}
        {canExpandOrCollapseLines && onToggleExpandAllLines && (
          <Tooltip
            text={areLinesExpanded ? `collapse non diff lines: ${path}` : `expand all lines: ${path}`}
            direction="s"
          >
            <button
              onClick={onToggleExpandAllLines}
              className={`Button Button--iconOnly Button--invisible flex-shrink-0 ${
                areLinesExpanded ? '' : `js-expand-all-difflines-button`
              }`}
              aria-label={areLinesExpanded ? `collapse non diff lines: ${path}` : `expand all lines: ${path}`}
              data-file-path={path}
            >
              {areLinesExpanded ? <FoldIcon /> : <UnfoldIcon />}
            </button>
          </Tooltip>
        )}
      </div>
      <div className="d-flex flex-row flex-justify-end flex-1 flex-order-1 flex-sm-order-2 flex-items-center">
        <div className="d-flex mr-2 flex-justify-end flex-items-center flex-1">
          {!isSubmodule && (
            <DiffStats
              linesAdded={linesAdded}
              linesDeleted={linesDeleted}
              linesChanged={linesChanged}
              tooltipDirection="sw"
              {...diffStatsProps}
            />
          )}
        </div>
        {isBinary && (
          <div className="d-flex flex-items-center">
            <code
              className={clsx('px-2', isNegative && 'fgColor-danger', !isNegative && 'fgColor-success')}
            >{`${size}`}</code>
            {rightSideContent}
          </div>
        )}
        {canToggleRichDiff && (
          <SegmentedControl
            aria-label="File view"
            size="small"
            className="mx-2"
            onChange={onToggleDiffDisplay ? index => onToggleDiffDisplay(index === 1) : undefined}
          >
            <SegmentedControl.IconButton
              aria-label="Display the source diff"
              defaultSelected={!defaultToRichDiff}
              icon={CodeIcon}
            />
            <SegmentedControl.IconButton
              aria-label="Display the rich diff"
              defaultSelected={defaultToRichDiff}
              icon={FileIcon}
            />
          </SegmentedControl>
        )}
        {rightSideContent}
      </div>
    </div>
  )
}
