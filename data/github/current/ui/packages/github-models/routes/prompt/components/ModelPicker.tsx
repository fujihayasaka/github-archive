import type {Model} from '@github-ui/marketplace-common'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {ChevronDownIcon} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {useQuery} from '@github-ui/react-query'
import {useEffect, useRef, useState} from 'react'
import {ModelsAvatar} from '../../../components/ModelsAvatar'
import {normalizeModelPublisher} from '../../../utils/normalize-model-strings'
import type {ModelDetails} from '../../../types'
import {useModelDetailsQuery} from '../hooks/use-model-details-query'
import {userHasAccessToModel} from '../../../utils/model-access'
import styles from './ModelPicker.module.css'

export default function ModelPicker({
  modelId,
  restrictedModels,
  onSelect,
}: {
  modelId?: string
  restrictedModels: string[]
  onSelect(model: Model, modelDetails?: ModelDetails): void
}) {
  const {data: models, isLoading: isLoadingModels} = useQuery<Model[]>({
    queryKey: ['github-models', 'models'],
    initialData: [],
    async queryFn() {
      const res = await verifiedFetchJSON('/marketplace/models')
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
  })

  const [showPanel, setShowPanel] = useState(false)
  const [filter, setFilter] = useState('')
  const [selectedModel, setSelectedModel] = useState<Model>(() => models?.find(m => m.id === modelId) || ({} as Model))

  const anchorRef = useRef<HTMLButtonElement>(null)
  const selectedModelElement = useRef<HTMLLIElement | null>(null)

  const {data: modelDetails, isFetching: isFetchingModelDetails} = useModelDetailsQuery(
    selectedModel?.registry,
    selectedModel?.name,
  )

  useEffect(() => {
    if (showPanel) {
      selectedModelElement.current?.scrollIntoView()
    }
  }, [showPanel])

  const filteredModels = models.filter(
    m =>
      m.task === 'chat-completion' &&
      (m.friendly_name.toLowerCase().includes(filter.toLowerCase()) ||
        normalizeModelPublisher(m.publisher).toLowerCase().includes(filter.toLowerCase())) &&
      userHasAccessToModel(m.name, restrictedModels),
  )

  useEffect(() => {
    if (isFetchingModelDetails || !modelDetails) {
      return
    }

    if (selectedModel.id === modelId) {
      setShowPanel(false)
      return
    }

    onSelect(selectedModel, modelDetails)
  }, [isFetchingModelDetails, selectedModel, modelId, modelDetails, onSelect])

  return (
    <div>
      <Button ref={anchorRef} onClick={() => setShowPanel(true)} aria-label="Select model" className={styles.button}>
        <div className="d-flex gap-2 flex-items-center">
          {selectedModel.name && <ModelsAvatar model={selectedModel} size={18} />}
          <div className={styles.dropdown}>{selectedModel.name ? selectedModel.friendly_name : 'Select model'}</div>
          <div className="fgColor-muted">
            <ChevronDownIcon />
          </div>
        </div>
      </Button>
      <SelectPanel
        open={showPanel}
        anchorRef={anchorRef}
        onSubmit={() => setShowPanel(false)}
        onCancel={() => setShowPanel(false)}
        title="Select model"
        selectionVariant="instant"
      >
        <SelectPanel.Header>
          <SelectPanel.SearchInput
            aria-label="Filter models"
            value={filter}
            onChange={e => setFilter(e.target.value)}
          />
        </SelectPanel.Header>

        {isLoadingModels ? (
          // As of shipping, we have 16 models so we show 19 loading skeletons to avoid layout shift
          Array.from({length: 16}).map((_, i) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <ActionList.Item key={i} disabled>
              <ActionList.LeadingVisual>
                <LoadingSkeleton width="20px" variant="rounded" />
              </ActionList.LeadingVisual>
              <LoadingSkeleton variant="rounded" />
            </ActionList.Item>
          ))
        ) : (
          <ActionList>
            {filteredModels.map(m => (
              <ActionList.Item
                key={m.id}
                onSelect={() => setSelectedModel(m)}
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
        )}
      </SelectPanel>
    </div>
  )
}
