import {ModelsAvatar} from '@github-ui/github-models/ModelsAvatar'
import {normalizeModelPublisher} from '@github-ui/github-models/NormalizeModels'
import type {Model} from '@github-ui/marketplace-common'
import {ChevronDownIcon} from '@primer/octicons-react'
import {ActionList, Truncate} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useEffect, useRef, useState} from 'react'
import {useModels} from '../contexts/ModelsContext'
import styles from './ModelPicker.module.css'

export default function ModelPicker({
  selectedModel,
  onSelect,
}: {
  selectedModel: Model | undefined
  onSelect(model: Model): void
}) {
  const models = useModels()

  const [filter, setFilter] = useState('')
  const filteredModels = models.filter(
    m =>
      m.friendly_name.toLowerCase().includes(filter.toLowerCase()) ||
      normalizeModelPublisher(m.publisher).toLowerCase().includes(filter.toLowerCase()),
  )

  const anchorRef = useRef<HTMLButtonElement>(null)
  const selectedModelElement = useRef<HTMLLIElement | null>(null)
  const [showPanel, setShowPanel] = useState(false)
  useEffect(() => {
    if (showPanel) {
      selectedModelElement.current?.scrollIntoView()
    }
  }, [showPanel])

  const modelDisplayName = selectedModel?.friendly_name || 'Select model'

  return (
    <SelectPanel
      anchorRef={anchorRef}
      onSubmit={() => setShowPanel(false)}
      onCancel={() => setShowPanel(false)}
      title="Select model"
      selectionVariant="instant"
    >
      {/* there is no alternative way to specify content alignment for now */}
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <SelectPanel.Button
        alignContent="start"
        leadingVisual={selectedModel?.name ? () => <ModelsAvatar model={selectedModel} size={18} /> : undefined}
        trailingAction={() => <ChevronDownIcon className="color-fg-muted" />}
        ref={anchorRef}
        className={clsx('d-flex flex-items-center flex-1', styles.modelPickerName)}
        labelWrap
      >
        <Truncate maxWidth={'100%'} title={modelDisplayName}>
          {modelDisplayName}
        </Truncate>
      </SelectPanel.Button>

      <SelectPanel.Header>
        <SelectPanel.SearchInput aria-label="Filter models" value={filter} onChange={e => setFilter(e.target.value)} />
      </SelectPanel.Header>

      <ActionList>
        {filteredModels.map(m => (
          <ActionList.Item
            key={m.id}
            onSelect={() => onSelect(m)}
            ref={m.id === selectedModel?.id ? selectedModelElement : null}
            selected={m.id === selectedModel?.id}
          >
            <ActionList.LeadingVisual>
              <ModelsAvatar model={m} size={20} />
            </ActionList.LeadingVisual>
            {m.friendly_name}
          </ActionList.Item>
        ))}
      </ActionList>
    </SelectPanel>
  )
}
