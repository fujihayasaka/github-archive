import {testIdProps} from '@github-ui/test-id-props'
import {modelsCatalogPath} from '@github-ui/paths'
import {useEffect, useState, useRef} from 'react'
import {ActionList, ActionMenu, IconButton, Button} from '@primer/react'
import {ChevronDownIcon, InfoIcon} from '@primer/octicons-react'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {SelectPanel} from '@primer/react/experimental'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useQuery} from '@github-ui/react-query'
import type {Model} from '@github-ui/marketplace-common'
import {SidebarSelectionOptions, type GettingStartedPayload} from '../../../types'
import {normalizeModelPublisher} from '../../../utils/normalize-model-strings'
import {ModelsAvatar} from '../../../components/ModelsAvatar'
import ModelInfo from '../../../components/ModelDetailsSidebar/ModelInfo'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {userHasAccessToModel} from '../../../utils/model-access'

export default function ModelSwitcher({
  model,
  onComparisonMode,
  onSelect,
  handleSetSidebarTab,
  variant,
}: {
  model?: Model
  onComparisonMode: boolean
  onSelect(model: Model): void
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
  variant?: 'default' | 'compare_button'
}) {
  const {restrictedModels} = useRoutePayload<GettingStartedPayload>()
  const [showPanel, setShowPanel] = useState(false)
  const [filter, setFilter] = useState('')

  const anchorRef = useRef<HTMLButtonElement>(null)
  const selectedModelElement = useRef<HTMLLIElement | null>(null)

  const {data: models, isLoading: isLoadingModels} = useQuery<Model[]>({
    queryKey: ['github-models', 'models'],
    initialData: [],
    async queryFn() {
      const res = await verifiedFetchJSON('/marketplace/models')
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
  })

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

  return (
    <div className="d-flex flex-items-center">
      {variant === 'compare_button' ? (
        <Button
          variant="default"
          ref={anchorRef}
          onClick={() => setShowPanel(true)}
          aria-label="Select model to compare"
          {...testIdProps('compare-model-button')}
        >
          Compare
        </Button>
      ) : (
        <Button
          variant={model ? 'default' : 'primary'}
          ref={anchorRef}
          onClick={() => setShowPanel(true)}
          aria-label="Switch model"
          leadingVisual={model && <ModelsAvatar model={model} size={18} />}
          trailingVisual={<ChevronDownIcon />}
          className={model && 'bgColor-default'}
          {...testIdProps('model-friendly-name')}
        >
          <span className={model && 'fgColor-muted'}>Model:</span> {model ? model.friendly_name : 'Select a Model'}
        </Button>
      )}
      <SelectPanel
        open={showPanel}
        anchorRef={anchorRef}
        onSubmit={() => setShowPanel(false)}
        onCancel={() => setShowPanel(false)}
        title={variant === 'compare_button' ? 'Select model' : 'Switch model'}
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
                onSelect={() => {
                  if (m.id === model?.id) {
                    setShowPanel(false)
                    return
                  }

                  onSelect(m)
                }}
                ref={m.id === model?.id ? selectedModelElement : null}
                selected={m.id === model?.id}
              >
                <ActionList.LeadingVisual>
                  <ModelsAvatar model={m} size={20} />
                </ActionList.LeadingVisual>
                {m.friendly_name}
              </ActionList.Item>
            ))}
          </ActionList>
        )}

        <SelectPanel.Footer>
          <SelectPanel.SecondaryAction variant="link" href={modelsCatalogPath()}>
            View all models
          </SelectPanel.SecondaryAction>
        </SelectPanel.Footer>
      </SelectPanel>
      {model && onComparisonMode && (
        <div className="ml-2 hide-sm">
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton icon={InfoIcon} aria-label="Show model info" {...testIdProps('model-info-button')} />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay width="xlarge" side="outside-left">
              <ActionList>
                <div className="border-bottom borderColor-default px-3 pt-2 pb-3" {...testIdProps('model-info-menu')}>
                  <h1 className="h4">Details</h1>
                </div>
                <ModelInfo headingLevel="h2" model={model} renderAs="listitem" />
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </div>
      )}
      {model && variant !== 'compare_button' && (
        <div className="hide-lg hide-xl ml-2">
          <IconButton
            icon={InfoIcon}
            aria-label="Show model info"
            onClick={() => handleSetSidebarTab(SidebarSelectionOptions.DETAILS)}
          />
        </div>
      )}
    </div>
  )
}
