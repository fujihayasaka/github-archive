import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import type {Location} from 'react-router-dom'

import {SparkNavigation} from './copilot-immersive/SparkNavigation'
import {SPARK_PLUGIN_ID, SPARK_PLUGIN_NAME} from './utils/constants'

const SPARK_PATH_REGEX = /\/copilot\/spark/

export class SparkPlugin implements ImmersivePlugin {
  public id = SPARK_PLUGIN_ID

  public displayName = SPARK_PLUGIN_NAME

  public routes = [SPARK_PATH_REGEX]

  public matchView(location: Location): boolean {
    return this.routes.some(route => route.test(location.pathname))
  }

  public NavigationComponent = SparkNavigation
}
