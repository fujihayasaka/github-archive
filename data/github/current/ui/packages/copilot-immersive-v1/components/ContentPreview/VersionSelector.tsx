import {ActionList, ActionMenu} from '@primer/react'

import {type PreviewableContent, stripVersionFromId} from './content-preview-types'
import {useContentPreview} from './ContentPreviewContext'
import {VersionName} from './VersionName'
import styles from './VersionSelector.module.css'

export interface VersionSelectorProps {
  item: PreviewableContent
}

export function VersionSelector({item}: VersionSelectorProps) {
  const {versionedItems, openItem} = useContentPreview()

  const unversionedId = stripVersionFromId(item.id)
  const versions = versionedItems.get(unversionedId) ?? []

  if (versions.length <= 1) return null

  const currentVersionIndex = versions.indexOf(item.id)

  return (
    <ActionMenu>
      <ActionMenu.Button variant="invisible" className={styles.anchor}>
        <VersionName version={currentVersionIndex + 1} />
      </ActionMenu.Button>

      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">
          {versions.map((versionId, i) => (
            <ActionList.Item key={versionId} onSelect={() => openItem(versionId)} selected={versionId === item.id}>
              <ActionList.LeadingVisual>
                <VersionName version={i + 1} />
              </ActionList.LeadingVisual>
              Version {i + 1}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
