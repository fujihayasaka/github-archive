import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {codeQualityAppBuilder} from './config/app-builder'

import {repoCodeQualityIndexRoute} from './routes/repo-code-quality-index-route'
import {RepoCodeQualityIndex} from './routes/RepoCodeQualityIndex'
import {repoCodeQualityShowRoute} from './routes/repo-code-quality-show-route'
import {RepoCodeQualityShow} from './routes/RepoCodeQualityShow'

export const codeQualityApp = codeQualityAppBuilder.createDataRouterAppFromRoutes([
  repoCodeQualityIndexRoute.toRoute({Component: RepoCodeQualityIndex}),
  repoCodeQualityShowRoute.toRoute({Component: RepoCodeQualityShow}),
])
registerDataRouterApp(codeQualityApp)
