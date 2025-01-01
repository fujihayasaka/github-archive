import type {RouteRegistration} from '@github-ui/react-core/app-routing-types'
import {render, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import type {PropsWithChildren} from 'react'
import {Route, Routes} from 'react-router-dom'

import {App} from '../App'
import {CurrentOrgRepoProvider} from '../contexts/CurrentOrgRepoContext'
import {
  businessCustomPropertiesRoute,
  definitionsRoute,
  detailsBusinessOrgPropertyDefinitionRoute,
  editDefinitionRoute,
  propertiesRoute,
  repoCustomPropertiesRoute,
} from '../custom-properties'

export const renderPropertyDefinitionsComponent = generateRoutedRender({
  pathname: '/organizations/acme/settings/custom-properties',
  routes: [definitionsRoute],
})

export const renderPropertyDefinitionsComponentAtEnterpriseLevel = generateRoutedRender({
  pathname: '/enterprises/acme-corp/settings/custom-properties',
  routes: [businessCustomPropertiesRoute],
})

export const renderRepoSettingsCustomPropertiesComponent = generateRoutedRender({
  pathname: '/acme/smile/settings/custom-properties',
  routes: [propertiesRoute],
})

export const renderPropertyDefinitionComponent = generateRoutedRender({
  pathname: '/organizations/acme/settings/custom-property/environment',
  routes: [editDefinitionRoute],
})

export const renderBusinessOrgPropertyDefinitionDetailsComponent = generateRoutedRender({
  pathname: '/enterprises/acme-corp/settings/custom-property/organizations/acme/environment',
  routes: [detailsBusinessOrgPropertyDefinitionRoute],
})

export const renderRepoCustomPropertiesComponent = generateRoutedRender({
  pathname: '/acme/smile/custom-properties',
  routes: [repoCustomPropertiesRoute],
})

interface RoutedRenderArgs {
  pathname: string
  routes: RouteRegistration[]
}

function generateRoutedRender({pathname, routes}: RoutedRenderArgs) {
  return function (ui: React.ReactElement, options?: TestRenderOptions) {
    return render(ui, {
      wrapper: ({children}) => (
        <Routes>
          {routes.map(route => (
            <Route
              key={route.path}
              path={route.path || pathname}
              element={
                <App>
                  <WrapperWithA11yMessage>
                    <CurrentOrgRepoProvider>{children}</CurrentOrgRepoProvider>
                  </WrapperWithA11yMessage>
                </App>
              }
            />
          ))}
        </Routes>
      ),
      routes,
      pathname,
      ...options,
    })
  }
}

function WrapperWithA11yMessage({children}: PropsWithChildren) {
  return (
    <>
      <div id="js-global-screen-reader-notice" aria-live="polite" aria-atomic="true" data-testid="sr-message" />
      {children}
    </>
  )
}
