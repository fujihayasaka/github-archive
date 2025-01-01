import {registerDataRouterApp} from '@github-ui/react-core/register-app'

import {appBuilder} from './config/app'

import {accessPolicyShow} from './routes/access-policy-show-route'
import {AccessPolicyShow} from './routes/AccessPolicyShow'

export const app = appBuilder.createDataRouterAppFromRoutes([accessPolicyShow.toRoute({Component: AccessPolicyShow})])

registerDataRouterApp(app)
