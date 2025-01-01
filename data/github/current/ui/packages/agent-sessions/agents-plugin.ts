import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import type {Location} from 'react-router-dom'
import {AgentsView} from './components/AgentsView'
import {AgentsViewNavigation} from './components/AgentsViewNavigation'
import {AGENTS_PLUGIN_ID, AGENTS_PLUGIN_NAME} from './utils/constants'

const AGENTS_REGEX = /\/copilot\/agents/

export class AgentsPlugin implements ImmersivePlugin {
  public id = AGENTS_PLUGIN_ID

  public displayName = AGENTS_PLUGIN_NAME

  public matchPage(location: Location): boolean {
    if (!location) return false

    return AGENTS_REGEX.test(location.pathname)
  }

  public matchView(location: Location): boolean {
    if (!location) return false

    return AGENTS_REGEX.test(location.pathname)
  }

  public routes = [AGENTS_REGEX]

  // public PageComponent = PipesPreviewArea

  public ViewComponent = AgentsView

  public NavigationComponent = AgentsViewNavigation
}
