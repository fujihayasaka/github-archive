import {useRef, useState} from 'react'
import {clsx} from 'clsx'
import {useResponsiveValue, LinkButton} from '@primer/react'
import {CommandPaletteIcon} from '@primer/octicons-react'
import type {GettingStarted, ShowModelPayload} from '../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {modelPlaygroundPath} from '@github-ui/paths'
import {templateRepositoryNwo} from '../../../utils/playground-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ModelDetails} from '../../../components/ModelDetailsSidebar/ModelDetails'
import GettingStartedDialog from '../../playground/components/GettingStartedDialog/GettingStartedDialog'
import {BreadcrumbHeader} from './BreadcrumbHeader'
import {GiveFeedback} from '../../../components/GiveFeedback'
import {PublisherAvatar} from '../../../components/PublisherAvatar'
import {UseThisModelButton} from '../../../components/UseThisModelButton'
import {userHasAccessToModel} from '../../../utils/model-access'

export function ModelOverviewHeader({
  model,
  gettingStarted,
  canUseModel,
}: {
  model: Model
  gettingStarted: GettingStarted
  canUseModel: boolean
}) {
  const {summary} = model
  const openInCodespacesUrl = `/codespaces/new?template_repository=${templateRepositoryNwo}`
  const [isGettingStartedDialogOpen, setGettingStartedDialogOpen] = useState(false)
  const {restrictedModels, isLoggedIn} = useRoutePayload<ShowModelPayload>()
  const useThisModelRef = useRef(null)
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const iconSize = isMobile ? 24 : 32

  const showAPIKey = userHasAccessToModel(model, restrictedModels)
  const showCodespacesSuggestion = showAPIKey

  return (
    <div className={clsx('d-flex flex-column gap-3', {'p-3 border-bottom': isMobile})}>
      {/*
        the breadcrumb header is redundant with the global navigation,
        so only include it when users are logged out (as logged out users do not see the global nav)
      */}
      {!isLoggedIn && <BreadcrumbHeader model={model} />}
      <div className="d-flex gap-3 flex-column flex-md-row">
        <div className="d-flex flex-auto gap-2 align-items-left">
          <PublisherAvatar
            logoUrl={model.logo_url}
            darkModeIcon={model.dark_mode_icon}
            publisher={model.publisher}
            size={iconSize}
          />
          <h1 className={isMobile ? 'h4' : 'h3'}>{model.friendly_name}</h1>
        </div>

        {isMobile && <span>{summary}</span>}
        {isMobile && <ModelDetails model={model} direction="row" />}

        <div className={clsx('d-flex gap-2', {'width-full': isMobile})}>
          {!isMobile && <GiveFeedback />}
          <div className="flex-1 d-flex gap-2 flex-column flex-md-row">
            {canUseModel && (
              <LinkButton
                variant="default"
                block={isMobile}
                href={modelPlaygroundPath(model)}
                leadingVisual={CommandPaletteIcon}
                tabIndex={0}
              >
                Playground
              </LinkButton>
            )}
            {showAPIKey && (
              <UseThisModelButton
                tabIndex={0}
                block={isMobile}
                ref={useThisModelRef}
                variant="primary"
                model={model}
                hideLabelOnSmallScreens={false}
                onClick={() => setGettingStartedDialogOpen(true)}
              />
            )}
          </div>
          {isGettingStartedDialogOpen && (
            <GettingStartedDialog
              openInCodespaceUrl={openInCodespacesUrl}
              onClose={() => setGettingStartedDialogOpen(false)}
              showCodespacesSuggestion={showCodespacesSuggestion}
              gettingStarted={gettingStarted}
              modelName={model.name}
              returnFocusRef={useThisModelRef}
            />
          )}
        </div>
      </div>
    </div>
  )
}
