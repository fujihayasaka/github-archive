import {stageColumn} from '../../../mocks/data/columns'
import {test} from '../../fixtures/test-extended'
import {activeElementHasAncestor} from '../../helpers/dom/assertions'

test.describe('Adding cards', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'board',
      sliceBy: {
        columnId: stageColumn.id,
      },
    })
  })

  test('slice panel is next focus target after view context menu', async ({page, memex}) => {
    // set focus on view options menu and tab 1 time
    await memex.viewOptionsMenu.open()
    await memex.viewOptionsMenu.close()
    await page.keyboard.press('Tab')

    // Verify that the focus is now in the slice panel
    await activeElementHasAncestor(page, 'slicer-panel')
  })
})
