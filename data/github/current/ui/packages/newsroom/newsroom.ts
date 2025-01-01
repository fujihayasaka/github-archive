import {App} from './App'
import {Newsroom} from './routes/Home/Newsroom'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {PressReleases} from './routes/PressReleases/PressReleases'
import {CategoryPage} from './routes/Category/Category'

registerNavigatorApp('newsroom', () => ({
  App,
  routes: [
    jsonRoute({path: '/newsroom', Component: Newsroom}),
    jsonRoute({path: '/newsroom/press-releases', Component: CategoryPage}),
    jsonRoute({path: '/newsroom/press-releases/:topic', Component: PressReleases}),
  ],
}))
