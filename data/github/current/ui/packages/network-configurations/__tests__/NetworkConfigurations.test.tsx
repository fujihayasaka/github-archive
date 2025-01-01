import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {NetworkConfigurations} from '../routes/NetworkConfigurations'
import {getNetworkConfigurationsRoutePayload} from '../test-utils/mock-data'
import {NetworkConfigurationConsts} from '../constants/network-configuration-consts'

test('Renders the NetworkConfigurations Business Empty State card', () => {
  const payload = getNetworkConfigurationsRoutePayload()
  payload.networks = []
  payload.isBusiness = true
  payload.userCanEditNetworkConfiguration = true
  payload.orgCanEditNetworkConfiguration = true
  render(<NetworkConfigurations />, {routePayload: payload})
  expect(screen.getByText('Hosted compute networking')).toBeInTheDocument()
  expect(
    screen.getByText(NetworkConfigurationConsts.noNetworkConfigurationsAddedDescriptionBusiness),
  ).toBeInTheDocument()
})

test('Renders the NetworkConfigurations Org Empty State card', () => {
  const payload = getNetworkConfigurationsRoutePayload()
  payload.networks = []
  payload.userCanEditNetworkConfiguration = true
  payload.orgCanEditNetworkConfiguration = true
  render(<NetworkConfigurations />, {routePayload: payload})
  expect(screen.getByText('Hosted compute networking')).toBeInTheDocument()
  expect(screen.getByText(NetworkConfigurationConsts.noNetworkConfigurationsAddedDescriptionOrg)).toBeInTheDocument()
})

test('Renders the NetworkConfigurations Org List', () => {
  const payload = getNetworkConfigurationsRoutePayload()
  payload.isBusiness = true
  payload.userCanEditNetworkConfiguration = true
  payload.orgCanEditNetworkConfiguration = true
  render(<NetworkConfigurations />, {routePayload: payload})
  expect(screen.getByText('Hosted compute networking')).toBeInTheDocument()
  expect(screen.getByText('test-name')).toBeInTheDocument()
})

test('Renders the NetworkConfigurations Org Empty State card, user cannot edit', () => {
  const payload = getNetworkConfigurationsRoutePayload()
  payload.networks = []
  payload.userCanEditNetworkConfiguration = false
  payload.orgCanEditNetworkConfiguration = true
  render(<NetworkConfigurations />, {routePayload: payload})
  expect(screen.getByText('Hosted compute networking')).toBeInTheDocument()
  expect(screen.getByText(NetworkConfigurationConsts.noNetworkConfigurationsAddedDescriptionOrg)).toBeInTheDocument()
  expect(screen.queryByText(NetworkConfigurationConsts.orgDisabledEmptyStateCardDescription)).not.toBeInTheDocument()
})

test('Renders the NetworkConfigurations Org List, user cannot edit', () => {
  const payload = getNetworkConfigurationsRoutePayload()
  payload.isBusiness = true
  payload.userCanEditNetworkConfiguration = false
  payload.orgCanEditNetworkConfiguration = true
  render(<NetworkConfigurations />, {routePayload: payload})
  expect(screen.getByText('Hosted compute networking')).toBeInTheDocument()
  expect(screen.getByText('test-name')).toBeInTheDocument()
})

test.each([true, false])('Renders OrgDisabledEmptyStateCard when policy disabled', userCanEditNetworkConfiguration => {
  const payload = getNetworkConfigurationsRoutePayload()
  payload.networks = []
  // user's permissions here don't really matter, so check both true and false
  payload.userCanEditNetworkConfiguration = userCanEditNetworkConfiguration
  payload.orgCanEditNetworkConfiguration = false
  render(<NetworkConfigurations />, {routePayload: payload})
  expect(screen.getByText(NetworkConfigurationConsts.orgDisabledEmptyStateCardDescription)).toBeInTheDocument()
})

test.each([true, false])('Renders NetworkConfigurationList when policy disabled', userCanEditNetworkConfiguration => {
  const payload = getNetworkConfigurationsRoutePayload()
  // user's permissions here don't really matter, so check both true and false
  payload.userCanEditNetworkConfiguration = userCanEditNetworkConfiguration
  payload.orgCanEditNetworkConfiguration = false
  render(<NetworkConfigurations />, {routePayload: payload})
  expect(screen.getByText('Hosted compute networking')).toBeInTheDocument()
  expect(screen.getByText('test-name')).toBeInTheDocument()
})
