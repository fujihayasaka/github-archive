import {MainPageEntrypointFuture} from './routes/MainPage'
import {CuratedImageDetailsPageEntrypointFuture} from './routes/CuratedImageDetailsPage'
import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {CuratedImageVersionDetailsPageEntrypointFuture} from './routes/CuratedImageVersionDetailsPage'
import {hostedComputeImsStafftoolsAppBuilder} from './config/app-builder'
import {hostedComputeImageDetailsRoute} from './routes/hosted-compute-image-details-route'
import {hostedComputeImageVersionDetailsRoute} from './routes/hosted-compute-image-version-details-route'
import {hostedComputeImsAdminRoute} from './routes/hosted-compute-ims-admin-route'

export const hostedComputeImsStafftoolsApp = hostedComputeImsStafftoolsAppBuilder.createDataRouterAppFromRoutes([
  hostedComputeImsAdminRoute.toRoute({
    Component: MainPageEntrypointFuture,
  }),
  hostedComputeImageDetailsRoute.toRoute({
    Component: CuratedImageDetailsPageEntrypointFuture,
  }),
  hostedComputeImageVersionDetailsRoute.toRoute({
    Component: CuratedImageVersionDetailsPageEntrypointFuture,
  }),
])

registerDataRouterApp(hostedComputeImsStafftoolsApp)
