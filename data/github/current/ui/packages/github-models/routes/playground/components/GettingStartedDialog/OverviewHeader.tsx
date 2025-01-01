import {useState, useMemo} from 'react'
import {Text, Box, Button, useResponsiveValue, LinkButton} from '@primer/react'
import {CodeIcon, CommandPaletteIcon, LinkExternalIcon} from '@primer/octicons-react'
import type {GettingStarted, ShowModelPayload} from '../../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {GettingStartedButtonClicked, templateRepositoryNwo} from '../../../../utils/playground-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ModelDetails} from '../ModelDetails'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
import GettingStartedDialog from './GettingStartedDialog'
import {sendEvent} from '@github-ui/hydro-analytics'
import {BreadcrumbHeader} from './BreadcrumbHeader'
import {GiveFeedback} from './GiveFeedback'
import ModelsAvatar from '../../../../components/ModelsAvatar'

export function OverviewHeader({model, gettingStarted}: {model: Model; gettingStarted: GettingStarted}) {
  const {summary} = model
  const openInCodespacesUrl = `/codespaces/new?template_repository=${templateRepositoryNwo}`
  const [isGettingStartedDialogOpen, setGettingStartedDialogOpen] = useState(false)
  const {canUseO1Models} = useRoutePayload<ShowModelPayload>()

  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const iconSize = isMobile ? 24 : 32

  const hideAPIKeyButton = () => {
    if (canUseO1Models) return false

    return ['o1-mini', 'o1-preview'].includes(model.name)
  }

  const showCodespacesSuggestion = ['o1-mini', 'o1-preview'].includes(model.name) ? canUseO1Models : true

  const canUseModel = useMemo(() => {
    if (model.task !== 'chat-completion') {
      return false
    }
    if (model.static_model) {
      return false
    }
    if (model.name === 'o1-mini' || model.name === 'o1-preview') {
      return canUseO1Models
    }

    return true
  }, [canUseO1Models, model])

  return (
    <Box
      sx={{
        display: 'flex',
        gap: 3,
        flexDirection: 'column',
        p: isMobile ? 3 : 0,
        backgroundColor: isMobile ? 'canvas.inset' : 'canvas.default',
        borderColor: 'border.default',
        borderBottomWidth: isMobile ? 1 : 0,
        borderBottomStyle: 'solid',
      }}
    >
      <BreadcrumbHeader model={model} />
      <div>
        <Box
          sx={{
            display: 'flex',
            justifyContent: 'center',
            flexDirection: ['column', 'column', 'row'],
            alignItems: 'center',
            gap: 3,
          }}
        >
          <Box
            sx={{
              flexGrow: [1, 1, 1],
              display: 'flex',
              minWidth: 0,
              alignItems: 'center',
              width: ['100%', '100%', 'auto'],
            }}
          >
            <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'center', gap: 2}}>
              <ModelsAvatar model={model} size={iconSize} />
              <h1 className={isMobile ? 'h4' : 'h3'}>{model.friendly_name}</h1>
            </Box>
          </Box>

          <Box
            sx={{
              display: ['flex', 'flex', 'none'],
              flexDirection: 'column',
              width: '100%',
              gap: 3,
            }}
          >
            <Text sx={{lineHeight: 1.5}}>{summary}</Text>
          </Box>

          <Box sx={{display: ['block', 'block', 'none'], width: '100%'}}>
            <ModelDetails model={model} direction="row" />
          </Box>

          <Box
            sx={{
              display: 'flex',
              gap: 2,
              width: ['100%', '100%', 'auto'],
              justifyContent: 'flex-end',
              flexGrow: [0, 0, 1],
              flexShrink: 0,
              flexDirection: ['column-reverse', 'column-reverse', 'row'],
            }}
          >
            <Box sx={{display: ['none', 'none', 'flex']}}>
              <GiveFeedback />
            </Box>
            <Box sx={{display: 'flex', flexDirection: ['column', 'row', 'row'], gap: 2}}>
              <>
                {canUseModel && (
                  <Button
                    variant="default"
                    as="a"
                    block={isMobile}
                    href={ModelUrlHelper.playgroundUrl(model)}
                    leadingVisual={CommandPaletteIcon}
                  >
                    Playground
                  </Button>
                )}
              </>

              {model.static_model ? (
                <LinkButton
                  block={isMobile}
                  leadingVisual={LinkExternalIcon}
                  variant="primary"
                  href={'https://aka.ms/oai/docs/limited-access-models'}
                >
                  Sign up for early access on Azure
                </LinkButton>
              ) : (
                <>
                  {!hideAPIKeyButton() && (
                    <Button
                      block={isMobile}
                      leadingVisual={CodeIcon}
                      variant="primary"
                      onClick={() => {
                        setGettingStartedDialogOpen(true)
                        sendEvent(GettingStartedButtonClicked, {
                          registry: model.registry,
                          model: model.name,
                          publisher: model.publisher,
                        })
                      }}
                    >
                      Get API key
                    </Button>
                  )}
                </>
              )}
            </Box>
            {isGettingStartedDialogOpen && (
              <GettingStartedDialog
                openInCodespaceUrl={openInCodespacesUrl}
                onClose={() => setGettingStartedDialogOpen(false)}
                showCodespacesSuggestion={showCodespacesSuggestion}
                gettingStarted={gettingStarted}
                modelName={model.name}
              />
            )}
          </Box>
        </Box>
      </div>
    </Box>
  )
}
