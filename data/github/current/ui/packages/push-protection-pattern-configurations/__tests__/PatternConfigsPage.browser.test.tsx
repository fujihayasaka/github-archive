import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {msw, http, HttpResponse} from '@github-ui/tests/msw'
import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
// eslint-disable-next-line no-restricted-imports
import {BoolSetting} from '@github-ui/secret-scanning/types/settings'
import {getPatternConfigsPageRoutePayload} from '../test-utils/mock-data'
import {pushProtectionPatternConfigurationsApp} from '../app'
import {patternConfigsPageRoute} from '../routes/pattern-configs-page-route'

describe('PatternConfigsPage', () => {
  beforeEach(() => {
    msw.use(
      http.patch(patternConfigsPageRoute.path, _info => {
        return HttpResponse.json({row_version: 'foo'}, {status: 200})
      }),
    )
  })

  it('renders the correct setting labels', async () => {
    const payload = getPatternConfigsPageRoutePayload({patternsCount: 1, has_parent: true})
    payload.pattern_config.provider_pattern_overrides[0]!.default_setting = BoolSetting.Disabled
    payload.pattern_config.provider_pattern_overrides[0]!.inherited_setting = BoolSetting.Enabled
    payload.pattern_config.provider_pattern_overrides[0]!.setting = BoolSetting.NotSet
    const {user} = render(pushProtectionPatternConfigurationsApp, patternConfigsPageRoute.path, {
      embeddedData: {
        payload: {
          patternConfigsPageRoute: payload,
        },
      },
    })

    await user.click(await screen.findByRole('button', {name: 'Default'}))
    // The default setting appears as a label next to the "GitHub default" radio item
    expect(screen.getByRole('menuitemradio', {name: /GitHub default/})).toHaveTextContent(/Disabled/)
    expect(screen.getByTestId('default-setting')).toHaveTextContent('Disabled')
    expect(screen.getByTestId('inherited-setting')).toHaveTextContent('Enabled')
  })

  it('does not render Inherited state column if config has no parent', async () => {
    await renderComponent({patternsCount: 1, has_parent: false})
    expect(await screen.findByTestId('default-setting')).toBeInTheDocument()
    expect(screen.queryByTestId('inherited-setting')).not.toBeInTheDocument()
  })

  it('updates button text when action menu item is selected', async () => {
    const {user} = await renderComponent()
    expect(screen.queryByRole('button', {name: 'Disabled'})).not.toBeInTheDocument()

    // Set to Disabled
    await user.click(await screen.findByRole('button', {name: 'Enabled'}))
    await user.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))
    expect(screen.queryByRole('button', {name: 'Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Disabled'})).toBeInTheDocument()

    // Set to Enabled
    await user.click(await screen.findByRole('button', {name: 'Disabled'}))
    await user.click(screen.getByRole('menuitemradio', {name: 'Enabled'}))
    expect(screen.getByRole('button', {name: 'Enabled'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Disabled'})).not.toBeInTheDocument()
  })

  it('has inactive buttons when settings are initial and active buttons when setting is changed', async () => {
    const {user} = await renderComponent()
    const submitBtn = await screen.findByRole('button', {name: 'Apply changes'})
    const cancelBtn = screen.getByRole('button', {name: 'Cancel'})

    // Inactive buttons
    expect(submitBtn).toHaveAttribute('data-inactive', 'true')
    expect(cancelBtn).toHaveAttribute('data-inactive', 'true')

    // Active after changing setting
    await user.click(await screen.findByRole('button', {name: 'Enabled'}))
    await user.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))
    expect(submitBtn).not.toHaveAttribute('data-inactive')
    expect(cancelBtn).not.toHaveAttribute('data-inactive')

    // Inactive after reverting setting
    await user.click(await screen.findByRole('button', {name: 'Disabled'}))
    await user.click(screen.getByRole('menuitemradio', {name: 'Enabled'}))
    expect(submitBtn).toHaveAttribute('data-inactive', 'true')
    expect(cancelBtn).toHaveAttribute('data-inactive', 'true')
  })

  it('preserves dropdown state and active buttons on paginate', async () => {
    const {user} = await renderComponent({patternsCount: 16})
    const submitBtn = await screen.findByRole('button', {name: 'Apply changes'})
    const cancelBtn = screen.getByRole('button', {name: 'Cancel'})
    expect(submitBtn).toHaveAttribute('data-inactive', 'true')
    expect(cancelBtn).toHaveAttribute('data-inactive', 'true')

    // Set to Disabled
    await user.click((await screen.findAllByRole('button', {name: 'Enabled'}))[0]!)
    await user.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))
    expect(screen.getByRole('button', {name: 'Disabled'})).toBeInTheDocument()
    expect(screen.getAllByRole('button', {name: 'Enabled'})).toHaveLength(14)
    expect(submitBtn).not.toHaveAttribute('data-inactive')
    expect(cancelBtn).not.toHaveAttribute('data-inactive')

    // Next page
    await user.click(screen.getByRole('button', {name: /Next/}))
    expect(screen.getByRole('button', {name: 'Enabled'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Disabled'})).not.toBeInTheDocument()
    expect(submitBtn).not.toHaveAttribute('data-inactive')
    expect(cancelBtn).not.toHaveAttribute('data-inactive')

    // Original page
    await user.click(screen.getByRole('button', {name: /Previous/}))
    expect(screen.getByRole('button', {name: 'Disabled'})).toBeInTheDocument()
    expect(screen.getAllByRole('button', {name: 'Enabled'})).toHaveLength(14)
    expect(submitBtn).not.toHaveAttribute('data-inactive')
    expect(cancelBtn).not.toHaveAttribute('data-inactive')
  })

  it('resets dropdowns on cancel click', async () => {
    const {user} = await renderComponent()

    // Set to Disabled
    await user.click(await screen.findByRole('button', {name: 'Enabled'}))
    await user.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))
    expect(screen.getByRole('button', {name: 'Disabled'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Enabled'})).not.toBeInTheDocument()

    // Cancel
    await user.click(screen.getByRole('button', {name: 'Cancel'}))
    expect(screen.queryByRole('button', {name: 'Disabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Enabled'})).toBeInTheDocument()
  })

  it('sets new settings to be the new initial settings on submit', async () => {
    const {user} = await renderComponent({patternsCount: 15})
    const submitBtn = screen.getByRole('button', {name: 'Apply changes'})

    // Set to Disabled
    await user.click(screen.getAllByRole('button', {name: 'Enabled'})[0]!)
    await user.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))
    expect(screen.getByRole('button', {name: 'Disabled'})).toBeInTheDocument()
    expect(screen.getAllByRole('button', {name: 'Enabled'})).toHaveLength(14)
    expect(submitBtn).not.toHaveAttribute('data-inactive')

    // Submit
    await waitFor(async () => {
      await user.click(submitBtn)
    })
    expect(submitBtn).toHaveAttribute('data-inactive', 'true')
    expect(screen.getByRole('button', {name: 'Disabled'})).toBeInTheDocument()
    expect(screen.getAllByRole('button', {name: 'Enabled'})).toHaveLength(14)
  })
})

async function renderComponent(args: Parameters<typeof getPatternConfigsPageRoutePayload>[0] = {}) {
  const view = render(pushProtectionPatternConfigurationsApp, patternConfigsPageRoute.path, {
    embeddedData: {
      payload: {
        patternConfigsPageRoute: getPatternConfigsPageRoutePayload(args),
      },
    },
  })
  // Wait for component to finish rendering properly
  await screen.findByRole('button', {name: 'Apply changes'})
  return view
}
