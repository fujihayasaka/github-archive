import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {App} from './App'
import {RepositoryCustomPropertyValuesIndexPage} from './routes/RepositoryCustomPropertyValuesIndexPage'
import {DefinitionsIndexPage} from './routes/DefinitionsIndexPage'
import {CustomPropertyDefinitionShowPage} from './routes/CustomPropertyDefinitionShowPage'

registerNavigatorApp('stafftools-custom-properties', () => ({
  App,
  routes: [
    jsonRoute({
      path: '/stafftools/repositories/:owner/:repo/custom_properties',
      Component: RepositoryCustomPropertyValuesIndexPage,
    }),
    jsonRoute({
      path: '/stafftools/users/:org/organization_custom_properties',
      Component: DefinitionsIndexPage,
    }),
    jsonRoute({
      path: '/stafftools/users/:org/organization_custom_properties/:name',
      Component: CustomPropertyDefinitionShowPage,
    }),
    jsonRoute({
      path: '/stafftools/enterprises/:enterprise/custom_properties',
      Component: DefinitionsIndexPage,
    }),
    jsonRoute({
      path: '/stafftools/enterprises/:enterprise/custom_properties/:name',
      Component: CustomPropertyDefinitionShowPage,
    }),
  ],
}))
