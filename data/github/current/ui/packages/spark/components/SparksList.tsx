import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useViewport} from '@github-ui/use-viewport'
import {Region, RegionState, useRegionState} from '@github-ui/workbench/hooks/use-region-state'
import type {Workbench} from '@github-ui/workbench/types/workbench-types'
import {
  DotFillIcon,
  GlobeIcon,
  LockIcon,
  RepoIcon,
  SparkleFillIcon,
  StarFillIcon,
  StarIcon,
  TrashIcon,
} from '@primer/octicons-react'
import {ActionList, IconButton, Label, RelativeTime, Spinner} from '@primer/react'
import {useMemo, useState} from 'react'

import {useDeleteWorkbenchMutation} from '../hooks/use-delete-workbench-mutation'
import {useFavoriteWorkbenchMutation} from '../hooks/use-favorite-workbench-mutation'
import {useSparkUrls} from '../hooks/use-spark-urls'
import {DeleteSparkDialog} from './DeleteSparkDialog'
import styles from './SparksList.module.css'

interface SparksListProps {
  items: Workbench[] | undefined
}

export const SparksList: React.FC<SparksListProps> = ({items}) => {
  const [openDeleteDialogItem, setOpenDeleteDialogItem] = useState<Workbench | null>(null)

  const {width} = useViewport()
  const {showUrl} = useSparkUrls()

  const editorState = useRegionState(Region.EDITOR)
  const editorDisabled = editorState === RegionState.DISABLED || editorState === RegionState.READ_ONLY

  const {favoriteWorkbench} = useFavoriteWorkbenchMutation()
  const {deleteWorkbench} = useDeleteWorkbenchMutation()

  const handleDeleteItem = (id: string) => {
    deleteWorkbench(id)
    setOpenDeleteDialogItem(null)
  }

  const handleDeleteClick = (item: Workbench) => {
    setOpenDeleteDialogItem(item)
  }

  const handleDeleteClose = () => {
    setOpenDeleteDialogItem(null)
  }

  const loading = items === undefined

  const sortedItems = useMemo(() => {
    return [...(items ?? [])].sort((a, b) => {
      // Handle cases where updatedAt might be undefined
      if (!a.updatedAt) return 1
      if (!b.updatedAt) return -1
      return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
    })
  }, [items])
  return (
    <>
      {loading && (
        <div className={styles.spinner}>
          <Spinner size="small" srText="Loading" />
        </div>
      )}
      {!loading && sortedItems.length === 0 && <span className={styles.blankslate}>No sparks yet</span>}
      {!loading && sortedItems.length > 0 && (
        <ListView title="List of sparks" className={styles.sparksList}>
          {sortedItems.map(item => (
            <ListItem
              key={item.id}
              title={
                <ListItemTitle
                  value={item.name}
                  href={showUrl(item.id, item.billableOwner?.login, item.friendlyName)}
                />
              }
              metadataContainerClassName={styles.ListItemMetadataContainer}
              metadata={
                width !== undefined &&
                width >= 768 && (
                  <ListItemMetadata>
                    {item.favorite ? (
                      <IconButton
                        variant="invisible"
                        icon={StarFillIcon}
                        title={`Unfavorite ${item.name} spark`}
                        aria-label="Unfavorite this spark"
                        className={styles.starfillIcon}
                        onClick={() => favoriteWorkbench({id: item.id, favorite: false})}
                      />
                    ) : (
                      <IconButton
                        variant="invisible"
                        icon={StarIcon}
                        title={`Unfavorite ${item.name} spark`}
                        aria-label="Favorite this spark"
                        onClick={() => favoriteWorkbench({id: item.id, favorite: true})}
                      />
                    )}
                  </ListItemMetadata>
                )
              }
              secondaryActions={
                <ListItemActionBar
                  label="Options"
                  staticMenuActions={[
                    {
                      key: 'favorite-spark',
                      render: () => {
                        if (width && width < 768) {
                          if (item.favorite) {
                            return (
                              <ActionList.Item onSelect={() => favoriteWorkbench({id: item.id, favorite: false})}>
                                <ActionList.LeadingVisual>
                                  <StarFillIcon />
                                </ActionList.LeadingVisual>
                                Unfavorite
                              </ActionList.Item>
                            )
                          } else {
                            return (
                              <ActionList.Item onSelect={() => favoriteWorkbench({id: item.id, favorite: true})}>
                                <ActionList.LeadingVisual>
                                  <StarIcon />
                                </ActionList.LeadingVisual>
                                Favorite
                              </ActionList.Item>
                            )
                          }
                        }
                      },
                    },
                    {
                      key: 'live-deployment-url',
                      render: () => {
                        if (item.deployUrl) {
                          return (
                            <ActionList.LinkItem href={item.deployUrl}>
                              <ActionList.LeadingVisual>
                                <GlobeIcon />
                              </ActionList.LeadingVisual>
                              <span className={styles.liveDeploymentText}>View live deployment</span>
                            </ActionList.LinkItem>
                          )
                        }
                      },
                    },
                    {
                      key: 'view-repository',
                      render: () => {
                        if (item.repositoryUrl) {
                          return (
                            <ActionList.LinkItem href={item.repositoryUrl}>
                              <ActionList.LeadingVisual>
                                <RepoIcon />
                              </ActionList.LeadingVisual>
                              View repository
                            </ActionList.LinkItem>
                          )
                        }
                      },
                    },
                    {
                      key: 'divider',
                      render: () => <ActionList.Divider />,
                    },
                    {
                      key: 'delete-spark',
                      render: () => (
                        <ActionList.Item variant="danger" onSelect={() => handleDeleteClick(item)}>
                          <ActionList.LeadingVisual>
                            <TrashIcon />
                          </ActionList.LeadingVisual>
                          Delete
                        </ActionList.Item>
                      ),
                    },
                  ]}
                />
              }
            >
              <ListItemLeadingContent>
                <ListItemLeadingVisual description="Sparkle icon" icon={SparkleFillIcon} className="fgColor-muted" />
              </ListItemLeadingContent>
              <ListItemMainContent>
                <ListItemDescription>
                  <ErrorBoundary fallback={null}>
                    {item.updatedAt && (
                      <>
                        Last updated <RelativeTime date={new Date(item.updatedAt)} />
                      </>
                    )}
                  </ErrorBoundary>
                  {item.deployUrl && (
                    <Label variant="default" size="large" className="ml-1">
                      <span className="fgColor-success d-flex flex-items-center gap-1">
                        <DotFillIcon /> Published
                      </span>
                    </Label>
                  )}
                  {editorDisabled && (
                    <Label variant="default" size="large" className="ml-1">
                      <span className="fgColor-attention d-flex flex-items-center">
                        <LockIcon size={16} className="mr-1" /> Read-only
                      </span>
                    </Label>
                  )}
                </ListItemDescription>
              </ListItemMainContent>
            </ListItem>
          ))}
        </ListView>
      )}
      {openDeleteDialogItem && (
        <DeleteSparkDialog workbench={openDeleteDialogItem} onCancel={handleDeleteClose} onConfirm={handleDeleteItem} />
      )}
    </>
  )
}
