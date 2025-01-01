import {test} from './fixtures/test-extended'

const colorSchemes = [
  'light',
  'light_high_contrast',
  'light_colorblind',
  'light_tritanopia',
  'dark',
  'dark_dimmed',
  'dark_high_contrast',
  'dark_colorblind',
  'dark_tritanopia',
] as const

test.describe('Themes', () => {
  /**
   * 'auto' themes are implicitly tested for
   * all other tests
   *
   * this ensures that each theme renders without error
   */
  for (const viewType of ['table', 'board'] as const) {
    for (const colorScheme of colorSchemes) {
      test(`In Theme ${colorScheme} ${viewType} render`, async ({memex}) => {
        // Object.keys won't maintain a union type, but flattens to string
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          colorScheme,
        })
        await memex.themes.expectThemeColorSchemeApplied(colorScheme)
      })
    }
  }

  test('A invalid color scheme defaults to the base scheme', async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      // @ts-expect-error we purposely pass an invalid option
      colorScheme: 'invalid_color_scheme',
    })
    await memex.themes.expectFallbackThemeColorSchemeApplied('invalid_theme_color', 'light')
  })

  test('a theme change occurs when the root element data props change', async ({memex, page}) => {
    await memex.navigateToStory('integrationTestsWithItems')
    await memex.themes.expectThemeColorSchemeApplied('light')

    await page.evaluate(() => {
      document.documentElement.setAttribute('data-color-mode', 'dark')
    })

    await memex.themes.expectThemeColorSchemeApplied('dark')
  })
})
