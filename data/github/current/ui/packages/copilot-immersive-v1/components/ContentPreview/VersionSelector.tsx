import {VersionName} from '@github-ui/copilot-chat/components/VersionName'
import {ActionList, ActionMenu} from '@primer/react'
import {useEffect} from 'react'

import {type PreviewableContent, stripVersionFromId} from './content-preview-types'
import {useContentPreview} from './ContentPreviewContext'
import styles from './VersionSelector.module.css'

export interface VersionSelectorProps {
  item: PreviewableContent
  onVersionSelect?: (versionName: string) => void
}

export function VersionSelector({item, onVersionSelect}: VersionSelectorProps) {
  const {versionedItems, openItem} = useContentPreview()

  const unversionedId = stripVersionFromId(item.id)
  const versions = versionedItems.get(unversionedId) ?? []

  const currentVersionIndex = versions.indexOf(item.id)
  useEffect(() => {
    if (onVersionSelect && versions.length > 1) {
      onVersionSelect(`Version${currentVersionIndex + 1}`)
    }
  }, [currentVersionIndex, onVersionSelect, versions.length])

  if (versions.length <= 1) return null

  return (
    <ActionMenu>
      <ActionMenu.Button variant="invisible" className={styles.anchor}>
        <VersionName version={currentVersionIndex + 1} data-testid="version-selector" />
      </ActionMenu.Button>

      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">
          {versions.map((versionId, i) => (
            <ActionList.Item
              key={versionId}
              onSelect={() => {
                openItem(versionId)
                if (onVersionSelect) {
                  onVersionSelect(`Version${i + 1}`)
                }
              }}
              selected={versionId === item.id}
            >
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
