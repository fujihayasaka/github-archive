import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {page, userEvent} from '@github-ui/tests/browser'
import {msw} from '@github-ui/tests/msw'
import {screen} from '@testing-library/react'
import type {ReactNode} from 'react'

import {CurrentOrgProvider} from '../../contexts/CurrentOrgContext'
import {PageBannerOutlet} from '../../contexts/PageBannerContext'
import {render as htmlRender, waitForStableDialog} from '../../test-utils/helpers'
import {customModelsIndexRouteHandlers, getMockPublicKey} from '../../test-utils/mocks'
import {AddCustomKeyButton} from '../AddCustomKeyButton'

describe('AddCustomKeyButton', () => {
  const publicKey = getMockPublicKey()

  beforeEach(async () => {
    await page.viewport(1024, 768)
    msw.resetHandlers()
    msw.use(...customModelsIndexRouteHandlers)
  })

  it('opens the add key dialog when clicked', async () => {
    render(<AddCustomKeyButton publicKey={publicKey} />)
    await userEvent.click(screen.getByRole('button', {name: 'Add custom key'}))
    await waitForStableDialog('Add custom key')
  })

  it('returns focus to the button on close', async () => {
    render(<AddCustomKeyButton publicKey={publicKey} />)

    const btn = screen.getByRole('button', {name: 'Add custom key'})
    await userEvent.click(btn)
    await waitForStableDialog('Add custom key')

    expect(btn).not.toHaveFocus()

    await userEvent.keyboard('{Escape}')

    expect(btn).toHaveFocus()
  })

  it('shows a success banner on successful key addition', async () => {
    render(<AddCustomKeyButton publicKey={publicKey} />)

    await userEvent.click(screen.getByRole('button', {name: 'Add custom key'}))
    await waitForStableDialog('Add custom key')

    await userEvent.fill(screen.getByLabelText('Name*'), 'Test Key')
    await userEvent.fill(screen.getByLabelText('Key*'), 'test-api-key')

    await userEvent.click(screen.getByRole('button', {name: 'Save'}))

    const banner = await screen.findByRole('banner', {name: 'Success'})
    expect(banner).toBeInTheDocument()
    expect(screen.getByText(/successfully added/)).toBeInTheDocument()
  })
})

function render(ui: ReactNode) {
  return htmlRender(
    <CurrentOrgProvider value="my-org">
      <div id="js-flash-container" />
      <PageBannerOutlet />
      {ui}
    </CurrentOrgProvider>,
  )
}
