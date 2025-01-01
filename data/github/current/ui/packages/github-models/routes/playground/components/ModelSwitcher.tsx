import {testIdProps} from '@github-ui/test-id-props'
import {useEffect, useState, useRef} from 'react'
import {Box, ActionList, ActionMenu, IconButton, Text} from '@primer/react'
import {ChevronDownIcon, InfoIcon} from '@primer/octicons-react'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {SelectPanel} from '@primer/react/experimental'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useQuery} from '@tanstack/react-query'
import type {Model} from '@github-ui/marketplace-common'
import {SidebarSelectionOptions} from '../../../types'
import {normalizeModelPublisher} from '../../../utils/normalize-model-strings'
import ModelsAvatar from '../../../components/ModelsAvatar'
import ModelInfo from './ModelInfo'

export default function ModelSwitcher({
  model,
  canUseO1Models,
  onComparisonMode,
  onSelect,
  handleSetSidebarTab,
}: {
  model: Model
  canUseO1Models: boolean
  onComparisonMode: boolean
  onSelect(model: Model): void
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
}) {
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

  const userHasAccessToModel = (m: Model) => {
    if (['o1-mini', 'o1-preview'].includes(m.name)) {
      return canUseO1Models
    }
    return true
  }

  const filteredModels = models.filter(
    m =>
      m.task === 'chat-completion' &&
      !m.static_model &&
      (m.friendly_name.toLowerCase().includes(filter.toLowerCase()) ||
        normalizeModelPublisher(m.publisher).toLowerCase().includes(filter.toLowerCase())) &&
      userHasAccessToModel(m),
  )

  return (
    <Box
      sx={{
        display: 'flex',
        maxWidth: '100%',
        minWidth: 0,
        alignItems: 'center',
      }}
    >
      <Box
        as="button"
        ref={anchorRef}
        onClick={() => setShowPanel(true)}
        aria-label="Switch model"
        sx={{
          display: 'flex',
          flex: 1,
          height: 32,
          bg: 'canvas.default',
          alignItems: 'center',
          minWidth: 0,
          maxWidth: '100%',
          borderColor: 'border.default',
          borderWidth: 1,
          borderStyle: 'solid',
          borderRadius: 2,
          boxShadow: 'var(--shadow-resting-small,var(--color-shadow-small))',
          transition: 'background-color 0.2s',
          ':hover': {
            bg: 'canvas.inset',
          },
        }}
      >
        <Box sx={{flexShrink: 0, mr: 2, display: 'flex'}}>
          <ModelsAvatar model={model} size={18} />
        </Box>
        <Box sx={{fontWeight: 'semibold', color: 'fg.muted', mr: 1}}>Model:</Box>
        <Box
          sx={{
            whiteSpace: 'nowrap',
            fontWeight: 'semibold',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            color: 'fg.default',
          }}
          {...testIdProps('model-friendly-name')}
        >
          {model.friendly_name}
        </Box>
        <Box sx={{color: 'fg.muted', ml: 1}}>
          <ChevronDownIcon />
        </Box>
      </Box>
      <SelectPanel
        open={showPanel}
        anchorRef={anchorRef}
        onSubmit={() => setShowPanel(false)}
        onCancel={() => setShowPanel(false)}
        title="Switch model"
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
                  if (m.id === model.id) {
                    setShowPanel(false)
                    return
                  }

                  onSelect(m)
                }}
                ref={m.id === model.id ? selectedModelElement : null}
                selected={m.id === model.id}
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
          <SelectPanel.SecondaryAction variant="link" href="/marketplace/models">
            View all models
          </SelectPanel.SecondaryAction>
        </SelectPanel.Footer>
      </SelectPanel>
      {onComparisonMode && (
        <div className="ml-2 hide-sm">
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton icon={InfoIcon} aria-label="Show model info" {...testIdProps('model-info-button')} />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay width="xlarge" side="outside-left">
              <ActionList>
                <div className="border-bottom borderColor-default px-3 pt-2 pb-3" {...testIdProps('model-info-menu')}>
                  <Text as="h1" sx={{fontSize: 1, fontWeight: 'bold', flex: 1}}>
                    Details
                  </Text>
                </div>
                <ModelInfo headingLevel="h2" model={model} />
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </div>
      )}
      <div className="hide-lg hide-xl ml-2">
        <IconButton
          icon={InfoIcon}
          aria-label="Show model info"
          onClick={() => handleSetSidebarTab(SidebarSelectionOptions.DETAILS)}
        />
      </div>
    </Box>
  )
}
