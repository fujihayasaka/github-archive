import {describe, it, expect} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {screen, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {TreeView} from '@primer/react'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {SelectionProvider} from '../../contexts/SelectionContext'
import {mockAccessPolicyShowPayload, mockModel, mockOrganizationAccessPolicy} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {ModelSelectionItem} from '../ModelSelectionItem'

describe('ModelSelectionItem', () => {
  it('renders for an allowed model in an allowlist', async () => {
    const model = mockModel()
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: [model.key]})

    render(<ModelSelectionItem model={model} />, {policy})

    const treeItem = screen.getByRole('treeitem', {name: model.friendlyName})
    expect(treeItem).toBeInTheDocument()
    expect(screen.getByTestId(`model-checkbox-${model.key}`)).toBeChecked()

    await userEvent.click(treeItem)

    expect(screen.getByTestId(`model-checkbox-${model.key}`)).not.toBeChecked()
  })

  it('renders for an allowed model in a blocklist', () => {
    const model = mockModel()
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: [model.key]})

    render(<ModelSelectionItem model={model} />, {policy})

    const treeItem = screen.getByRole('treeitem', {name: model.friendlyName})
    expect(treeItem).toBeInTheDocument()
    expect(screen.getByTestId(`model-checkbox-${model.key}`)).not.toBeChecked()
  })

  it('renders for a blocked model in an allowlist', () => {
    const model = mockModel()
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: []})

    render(<ModelSelectionItem model={model} />, {policy})

    const treeItem = screen.getByRole('treeitem', {name: model.friendlyName})
    expect(treeItem).toBeInTheDocument()
    expect(screen.getByTestId(`model-checkbox-${model.key}`)).not.toBeChecked()
  })

  it('renders for a blocked model in a blocklist', () => {
    const model = mockModel()
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: []})

    render(<ModelSelectionItem model={model} />, {policy})

    const treeItem = screen.getByRole('treeitem', {name: model.friendlyName})
    expect(treeItem).toBeInTheDocument()
    expect(screen.getByTestId(`model-checkbox-${model.key}`)).toBeChecked()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(
    <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
      <PublishersProvider models={routePayload.models} publishers={routePayload.publishers}>
        <SelectionProvider models={routePayload.models} publishers={routePayload.publishers}>
          <TreeView aria-label="ModelSelectionItem test tree">{component}</TreeView>
        </SelectionProvider>
      </PublishersProvider>
    </OrganizationAccessPolicyProvider>,
    {wrapper: withBaseProvidersWrapper()},
  )
}
