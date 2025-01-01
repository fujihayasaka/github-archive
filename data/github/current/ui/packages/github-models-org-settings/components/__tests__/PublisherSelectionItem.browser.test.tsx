import {describe, it, expect} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {screen, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {TreeView} from '@primer/react'
import type {AccessPolicyShowPayload} from '../../types'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {SelectionProvider} from '../../contexts/SelectionContext'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../../test-utils/mocks'
import {PublisherSelectionItem} from '../PublisherSelectionItem'

describe('PublisherSelectionItem', () => {
  it('renders', async () => {
    const models = [
      mockModel({key: 'mypub/blockedmodle', publisherId: 1, friendlyName: 'BlockedModel'}),
      mockModel({key: 'mypub/allowedmodel', publisherId: 1, friendlyName: 'AllowedModel'}),
      mockModel({key: 'otherpub/somemodel', publisherId: 2, friendlyName: 'OtherPublisherModel'}),
    ]
    const publisher = mockPublisher({id: 1, totalModels: 2, name: 'My Favorite Publisher'})
    const policy = mockOrganizationAccessPolicy({allowedModelKeys: ['mypub/allowedmodel']})

    render(<PublisherSelectionItem publisher={publisher} models={models} />, {models, policy})

    const publisherTreeItem = screen.getByRole('treeitem', {name: 'My Favorite Publisher'})
    expect(publisherTreeItem).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'My Favorite Publisher logo'})).toBeInTheDocument()
    expect(screen.getByTestId('publisher-checkbox-1')).toBePartiallyChecked()
    expect(screen.queryByTestId('publisher-checkbox-2')).not.toBeInTheDocument()
    expect(screen.queryByRole('group', {name: 'Models from My Favorite Publisher'})).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox', {name: 'Select AllowedModel'})).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox', {name: 'Select BlockedModel'})).not.toBeInTheDocument()

    // Expand publisher sub-tree that includes its models:
    publisherTreeItem.focus()
    await userEvent.keyboard('[ArrowRight]')

    expect(screen.getByRole('group', {name: 'Models from My Favorite Publisher'})).toBeInTheDocument()
    expect(screen.getByRole('checkbox', {name: 'Select AllowedModel'})).not.toBeChecked()
    expect(screen.getByRole('checkbox', {name: 'Select BlockedModel'})).toBeChecked()
    expect(screen.getByTestId('publisher-checkbox-1')).toBePartiallyChecked()

    // When you "click", you click the top-left corner, which for a list item is the "collapse" toggle,
    // so click slightly to the right to trigger the click of the checkbox.
    await userEvent.click(publisherTreeItem, {position: {x: 20, y: 2}})

    expect(screen.getByTestId('publisher-checkbox-1')).toBeChecked()
    expect(screen.getByRole('checkbox', {name: 'Select AllowedModel'})).toBeChecked()
    expect(screen.getByRole('checkbox', {name: 'Select BlockedModel'})).toBeChecked()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(
    <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
      <PublishersProvider models={routePayload.models} publishers={routePayload.publishers}>
        <SelectionProvider models={routePayload.models} publishers={routePayload.publishers}>
          <TreeView aria-label="PublisherSelectionItem test tree">{component}</TreeView>
        </SelectionProvider>
      </PublishersProvider>
    </OrganizationAccessPolicyProvider>,
    {wrapper: withBaseProvidersWrapper()},
  )
}
