import {useState} from 'react'
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
import {ModelsAvatar} from '../../../components/ModelsAvatar'
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
  const {restrictedModels} = useRoutePayload<ShowModelPayload>()

  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const iconSize = isMobile ? 24 : 32

  const showAPIKey = userHasAccessToModel(model.name, restrictedModels)
  const showCodespacesSuggestion = userHasAccessToModel(model.name, restrictedModels)

  return (
    <div className={`d-flex flex-column gap-3 ${isMobile && 'p-3 border-bottom'}`}>
      <BreadcrumbHeader model={model} />
      <div className={`d-flex gap-3 ${isMobile ? 'flex-column' : 'flex-row'}`}>
        <div className="width-full d-flex gap-2 align-items-left">
          <ModelsAvatar model={model} size={iconSize} />
          <h1 className={isMobile ? 'h4' : 'h3'}>{model.friendly_name}</h1>
        </div>

        {isMobile && <span>{summary}</span>}
        {isMobile && <ModelDetails model={model} direction="row" />}

        <div className={`d-flex gap-2 ${isMobile && 'width-full'}`}>
          {!isMobile && <GiveFeedback />}
          <div className={`flex-1 d-flex gap-2 ${isMobile ? 'flex-column' : 'flex-row'}`}>
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
            />
          )}
        </div>
      </div>
    </div>
  )
}
