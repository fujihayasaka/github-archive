import {test} from '../../fixtures/test-extended'
import {PWL_SKIP_REASON} from '../../helpers/pwl-spec-migration'

test.describe('Table Issue Types', () => {
  test('Renders column data for issue types', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('integrationTestsWithItems')

    await memex.tableView.cells.getIssueTypeCell(3).expectText('Batch')
    await memex.tableView.cells.getIssueTypeCell(5).expectText('Bug')
  })
})
