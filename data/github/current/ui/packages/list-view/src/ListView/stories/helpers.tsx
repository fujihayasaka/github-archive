// Use Avatar instead of GithubAvatar component to avoid importing the dependency
// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useActionBarResize} from '@github-ui/action-bar'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {CommentIcon, IssueClosedIcon, PencilIcon, TagIcon, TriangleDownIcon} from '@primer/octicons-react'
import {
  ActionList,
  ActionMenu,
  // eslint-disable-next-line no-restricted-imports
  Avatar,
  Button,
  Label as PrimerLabel,
  Link,
  SelectPanel,
  Token,
} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import type {Dispatch, SetStateAction} from 'react'
import {Fragment, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {ListItemActionBar} from '../../ListItem/ActionBar'
import {ListViewMetadata, type ListViewMetadataProps} from '../Metadata'
import {useListViewSelection} from '../SelectionContext'
import styles from './helpers.module.css'
import {
  branches,
  checkStates,
  iconMap,
  type Label,
  labels,
  type ListItemDescriptionAreaOption,
  type ListItemPrimaryAreaOption,
  relativeTimes,
  reviewStates,
  titles,
} from './mocks'

const getRandomEntry = <T extends string | object>(array: T[]) => array[Math.floor(Math.random() * array.length)]

/******************
 * COMMENT
 ******************/

export const Comments = ({count}: {count: number}) =>
  count ? (
    <>
      <CommentIcon size={16} /> {count}
    </>
  ) : null

/******************
 * LABEL
 ******************/

export const generateLabels = (index: number) => labels.slice(index, index * 3)

export const getLabelsDescription = (items: string[], truncatedLabelCount: number) => {
  const description = `Labels: ${items.slice(0, items.length - truncatedLabelCount).join(', ')}`

  if (truncatedLabelCount > 0) {
    return `${description}, and ${truncatedLabelCount} more;`
  }
  return `${description};`
}

export function Labels({items}: {items: Label[]}) {
  const [truncatedLabelCount, setTruncatedLabelCount] = useState(0)
  const lastVisibleLabelIndex = items.length - truncatedLabelCount - 1

  const labelRef = useRef<HTMLDivElement>(null)

  const recalculatedTruncatedLabelCount = useCallback(() => {
    if (labelRef?.current) {
      const childLabels = Array.from(labelRef.current.children) as HTMLDivElement[]
      const baseOffset = labelRef.current.offsetTop
      const breakIndex = childLabels.findIndex(item => item.offsetTop > baseOffset)
      setTruncatedLabelCount(breakIndex > 0 ? items.length - breakIndex : 0)
    }
  }, [items.length])

  useEffect(() => {
    // recalculate the truncated label count when the window is resized
    const curObserver = new ResizeObserver(() => {
      recalculatedTruncatedLabelCount()
    })

    if (labelRef?.current) {
      curObserver.observe(labelRef.current)
    }

    return () => {
      curObserver.disconnect()
    }
  }, [recalculatedTruncatedLabelCount])

  // using this to synchronize the rendering of the labels and the + badge
  useLayoutEffect(() => {
    recalculatedTruncatedLabelCount()
  }, [items.length, recalculatedTruncatedLabelCount])

  const labelsDescription = useMemo(() => {
    return getLabelsDescription(
      items.map(label => label.name),
      truncatedLabelCount,
    )
  }, [items, truncatedLabelCount])

  if (items.length === 0) {
    return null
  }

  return (
    <div className={styles.Box_0}>
      <div role="group" aria-label={labelsDescription} className={styles.Box_1}>
        <div ref={labelRef} className={styles.Box_2}>
          {items.map((label, index) => {
            const hidden = index > lastVisibleLabelIndex
            const {name, variant} = label
            return (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <Link key={index} muted>
                <PrimerLabel variant={variant} className={clsx({'sr-only': hidden})}>
                  {name}
                </PrimerLabel>
              </Link>
            )
          })}
        </div>
        {truncatedLabelCount > 0 && (
          <Tooltip
            align="right"
            direction="sw"
            text={items.map(label => label.name).join(', ')}
            className={styles.Tooltip_0}
          >
            <Token text={`+${truncatedLabelCount}`} />
          </Tooltip>
        )}
      </div>
    </div>
  )
}

/******************
 * STATUS ICON
 ******************/

export const generateStatusIcon = (type: 'Issues' | 'Pull Requests' | 'Deployments' | 'Repositories') => {
  const icons = iconMap[type] || iconMap['Issues']
  return getRandomEntry(icons as object[])
}

/******************
 * AVATAR
 ******************/

export const generateAvatar = () => {
  return <Avatar src="https://avatars.githubusercontent.com/u/92997159?v=4" className={styles.Avatar_0} />
}

/******************
 * TITLE
 ******************/

export const generateTitle = (type: ListItemPrimaryAreaOption, id: number) => {
  return titles[type][id]
}

/******************
 * DESCRIPTION
 ******************/

const reviews = reviewStates.map(({icon, color, description}) => (
  <Fragment key={description}>
    <Octicon icon={icon} size={12} color={color} />
    <span className={styles.Text_0}>{description}</span>
  </Fragment>
))

const checkStatuses = checkStates.map(({icon, color, count}) => (
  <Fragment key={count}>
    <Octicon icon={icon} color={color} />
    <span>{count}</span>
  </Fragment>
))

export const generateDescription = (type: ListItemDescriptionAreaOption) => {
  switch (type) {
    case 'Branch name':
      return getRandomEntry(branches)
    case 'Relative time':
      return `Updated ${getRandomEntry(relativeTimes)}`
    case 'Review state and checks':
      return (
        <span className={styles.Box_3}>
          {getRandomEntry(reviews)}· {getRandomEntry(checkStatuses)}
        </span>
      )
    default:
      return (
        <>
          {getRandomEntry(branches)} &middot; {getRandomEntry(reviews)} &middot; {getRandomEntry(checkStatuses)}
        </>
      )
  }
}

/******************
 * ListItem.ActionBar
 ******************/

export const SampleListItemActionBar = () => (
  <ListItemActionBar
    label="sample action bar"
    staticMenuActions={[
      {
        key: 'mark-as',
        render: () => <ActionList.Item>Mark as</ActionList.Item>,
      },
      {
        key: 'assign-to',
        render: () => <ActionList.Item>Assign</ActionList.Item>,
      },
      {
        key: 'set-label',
        render: () => <ActionList.Item>Label</ActionList.Item>,
      },
      {
        key: 'set-milestone',
        render: () => <ActionList.Item>Milestone</ActionList.Item>,
      },
      {
        key: 'add-to-project',
        render: () => <ActionList.Item>Project</ActionList.Item>,
      },
    ]}
  />
)

/******************
 * ListView.Metadata
 ******************/

const coloredCircle = (hexColor: string) => (
  <div
    style={{
      backgroundColor: hexColor,
      borderColor: hexColor,
    }}
    className={styles.Box_4}
  />
)

export const allLabelItems: ItemInput[] = [
  {text: 'bug', leadingVisual: () => coloredCircle('#d73a4a')},
  {text: 'documentation', leadingVisual: () => coloredCircle('#0075ca')},
  {text: 'duplicate', leadingVisual: () => coloredCircle('#cfd3d7')},
  {text: 'enhancement', leadingVisual: () => coloredCircle('#a2eeef')},
  {text: 'good first issue', leadingVisual: () => coloredCircle('#7057ff')},
]

type SampleSelectPanelProps = {
  nested?: boolean
  selectedItems: ItemInput[]
  setSelectedItems: Dispatch<SetStateAction<ItemInput[]>>
  actionKey: string
}

export const SampleSelectPanel = ({
  nested = false,
  selectedItems,
  setSelectedItems,
  actionKey,
}: SampleSelectPanelProps) => {
  const toggleButtonContainerRef = useRef<HTMLDivElement>(null)
  // eslint-disable-next-line react-compiler/react-compiler
  const toggleButtonContainer = toggleButtonContainerRef.current
  const {recalculateItemSize} = useActionBarResize()
  const [filter, setFilter] = useState('')
  const filteredItems = useMemo(
    () => allLabelItems.filter(item => item.text!.toLowerCase().includes(filter.toLowerCase())),
    [filter],
  )
  const [open, setOpen] = useState(false)
  const selectPanelProps = useMemo(
    () => ({
      title: `Select labels (${selectedItems.length})`,
      selected: selectedItems,
      onSelectedChange: setSelectedItems,
      items: filteredItems,
      onFilterChange: setFilter,
    }),
    [selectedItems, filteredItems, setSelectedItems],
  )

  useEffect(() => {
    if (!open && toggleButtonContainer && actionKey) recalculateItemSize(actionKey, toggleButtonContainer)
  }, [open, recalculateItemSize, actionKey, toggleButtonContainer])

  return (
    <SelectPanel
      renderAnchor={({children, ...anchorProps}) =>
        nested ? (
          <ActionList.Item {...anchorProps} role="menuitem">
            <ActionList.LeadingVisual>
              <TagIcon />
            </ActionList.LeadingVisual>
            Set label
          </ActionList.Item>
        ) : (
          <div ref={toggleButtonContainerRef}>
            <Button leadingVisual={TagIcon} trailingAction={TriangleDownIcon} {...anchorProps}>
              {children || 'Set label'}
            </Button>
          </div>
        )
      }
      {...selectPanelProps}
      open={open}
      onOpenChange={setOpen}
    />
  )
}

const sampleActionListItems = (
  <>
    <ActionList.Item role="menuitemradio">Foo</ActionList.Item>
    <ActionList.Item role="menuitemradio">Bar</ActionList.Item>
    <ActionList.Item role="menuitemradio">Baz</ActionList.Item>
  </>
)

export const SampleListViewMetadataWithActions = ({children, ...args}: ListViewMetadataProps) => {
  const [selectedLabels, setSelectedLabels] = useState([allLabelItems[2]!])
  const applyLabelsProps = useMemo(
    () => ({selectedItems: selectedLabels, setSelectedItems: setSelectedLabels}),
    [selectedLabels],
  )
  const {selectedCount} = useListViewSelection()
  return (
    <ListViewMetadata
      actionsLabel="Actions"
      actions={
        selectedCount < 1
          ? [
              {
                key: 'edit',
                render: isOverflowMenu => {
                  return isOverflowMenu ? (
                    <ActionList.Item>
                      <ActionList.LeadingVisual>
                        <PencilIcon />
                      </ActionList.LeadingVisual>
                      Edit
                    </ActionList.Item>
                  ) : (
                    <Button leadingVisual={PencilIcon}>Edit</Button>
                  )
                },
              },
            ]
          : [
              {
                key: 'apply-labels',
                render: isOverflowMenu => (
                  <SampleSelectPanel actionKey="apply-labels" nested={isOverflowMenu} {...applyLabelsProps} />
                ),
              },
              {
                key: 'mark-as',
                render: isOverflowMenu => (
                  <ActionMenu>
                    {isOverflowMenu ? (
                      <ActionMenu.Anchor>
                        <ActionList.Item>
                          <ActionList.LeadingVisual>
                            <IssueClosedIcon />
                          </ActionList.LeadingVisual>
                          Mark as...
                        </ActionList.Item>
                      </ActionMenu.Anchor>
                    ) : (
                      <ActionMenu.Button leadingVisual={IssueClosedIcon}>Mark as...</ActionMenu.Button>
                    )}

                    <ActionMenu.Overlay>
                      <ActionList>{sampleActionListItems}</ActionList>
                    </ActionMenu.Overlay>
                  </ActionMenu>
                ),
              },
            ]
      }
      {...args}
    >
      {children}
    </ListViewMetadata>
  )
}
