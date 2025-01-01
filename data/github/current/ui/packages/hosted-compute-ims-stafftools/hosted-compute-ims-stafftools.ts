import {App} from './App'
import {Main} from './routes/Main'
import {ListImageVersions} from './routes/ListImageVersions'
import {registerReactAppFactory} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerReactAppFactory('hosted-compute-ims-stafftools', () => ({
  App,
  routes: [
    jsonRoute({path: '/stafftools/hosted_compute_ims_admin', Component: Main}),
    jsonRoute({
      path: '/stafftools/hosted_compute_ims_admin/curated/:image_definition_id',
      Component: ListImageVersions,
    }),
  ],
}))
