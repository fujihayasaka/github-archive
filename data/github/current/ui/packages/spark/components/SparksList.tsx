import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {PencilIcon, SparkleFillIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {useCallback, useEffect, useState} from 'react'

import type {SparkList, SparkListItem} from '../utils/spark-types'
import EditDialog from './EditDialog'
import styles from './SparksList.module.css'

const SparksList: React.FC = () => {
  const [items, setItems] = useState<SparkListItem[]>([])
  const [openEditDialog, setOpenEditDialog] = useState(false)
  const [currentItem, setCurrentItem] = useState<SparkListItem | null>(null)
  const origin = ssrSafeLocation.origin

  useEffect(() => {
    async function fetchData() {
      try {
        const res = await verifiedFetchJSON('/copilot/spark/workbench', {method: 'GET'})
        if (res.ok) {
          const data = (await res.json()) as SparkList
          setItems(data.workbenches)
        }
      } catch {
        return
      }
    }
    void fetchData()
  }, [])

  const handleDelete = async (id: string) => {
    try {
      const res = await verifiedFetchJSON(`/copilot/spark/workbench/${id}`, {method: 'DELETE'})
      if (res.ok) {
        const filteredList = items.filter(item => item.id !== id)
        setItems(filteredList)
      }
    } catch {
      return
    }
  }

  const onEditClick = (item: SparkListItem) => {
    setOpenEditDialog(true)
    setCurrentItem(item)
  }

  const handleEditClose = () => {
    setOpenEditDialog(false)
    setCurrentItem(null)
  }

  const submitRename = useCallback(
    async ({id, name}: SparkListItem) => {
      try {
        const res = await verifiedFetchJSON(`/copilot/spark/workbench/${id}`, {method: 'POST', body: {id, name}})
        if (res.ok) {
          const newName: string = (await res.json()).name || ''
          if (newName) {
            const updatedItems = items.map(item => {
              if (item.id === id) {
                return {...item, name}
              }
              return item
            })
            setItems(updatedItems)
            handleEditClose()
          }
        }
      } catch {
        return
      }
    },
    [items],
  )

  return (
    items.length > 0 && (
      <>
        <ListView title="Recent sparks" className={styles.sparksList}>
          {items.map(item => (
            <ListItem
              key={item.id}
              title={<ListItemTitle value={item.name} href={`${origin}/copilot/spark/${item.id}`} />}
              secondaryActions={
                <ListItemActionBar
                  label="Options"
                  staticMenuActions={[
                    {
                      key: 'action-1',
                      render: () => (
                        <ActionList.Item onSelect={() => onEditClick(item)}>
                          <ActionList.LeadingVisual>
                            <PencilIcon />
                          </ActionList.LeadingVisual>
                          Edit spark
                        </ActionList.Item>
                      ),
                    },
                    // {
                    //   key: 'action-2',
                    //   render: () => (
                    //     <ActionList.Item>
                    //       <ActionList.LeadingVisual>
                    //         <GlobeIcon />
                    //       </ActionList.LeadingVisual>
                    //       View live deployment
                    //     </ActionList.Item>
                    //   ),
                    // },
                    // {
                    //   key: 'action-3',
                    //   render: () => (
                    //     <ActionList.Item>
                    //       <ActionList.LeadingVisual>
                    //         <ShareIcon />
                    //       </ActionList.LeadingVisual>
                    //       Share
                    //     </ActionList.Item>
                    //   ),
                    // },
                    {
                      key: 'action-4',
                      render: () => <ActionList.Divider />,
                    },
                    {
                      key: 'action-5',
                      render: () => (
                        <ActionList.Item variant="danger" onSelect={() => handleDelete(item.id)}>
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
                  {/* Last updated <RelativeTime date={new Date(item.updatedAt * 1000)} /> */}
                  {/* If deployed */}
                  {/* <span className="d-flex gap-1">
                    <DotFillIcon className="fgColor-success" /> Deployed
                  </span> */}
                </ListItemDescription>
              </ListItemMainContent>
            </ListItem>
          ))}
        </ListView>
        {openEditDialog && <EditDialog currentItem={currentItem} onCancel={handleEditClose} onSubmit={submitRename} />}
      </>
    )
  )
}

export default SparksList
