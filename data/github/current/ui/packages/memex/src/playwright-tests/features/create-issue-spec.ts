import {expect} from '@playwright/test'

import {DefaultMemex} from '../../mocks/data/memexes'
import {test} from '../fixtures/test-extended'
import {waitForRowCount} from '../helpers/table/assertions'

test.describe('IssueCreator', () => {
  test('carries a title to the creator', async ({memex, page}) => {
    await memex.navigateToStory('integrationTestsWithItems')
    await memex.omnibar.focusAndEnterText('#')
    const repo = page.getByRole('option', {
      name: 'memex',
    })
    await repo.click()
    const createNewIssueButton = page.getByTestId('create-new-issue')
    await test.expect(createNewIssueButton).toBeVisible()
    await memex.omnibar.focusAndEnterText('new issue title')
    await createNewIssueButton.click()

    await test
      .expect(page.getByRole('dialog').getByRole('textbox', {name: 'Add a title'}))
      .toHaveValue('new issue title')
  })

  test('ensures new content is copied, clearing old localStorage value', async ({memex, page}) => {
    await memex.navigateToStory('integrationTestsWithItems')
    await page.evaluate(() => {
      // manually seeding this because we can't import easily across the page eval boundary
      const prefix = ['projects-v2', 'session-store-v1', 'orgs', 'integration', 1, 'issue-creator'].join('/')
      // eslint-disable-next-line no-restricted-properties
      window.localStorage.setItem(`${prefix}.create-issue-title`, 'not-the-correct-title')
    })
    await memex.omnibar.focusAndEnterText('#')
    const repo = page.getByRole('option', {
      name: 'memex',
    })
    await repo.click()
    const createNewIssueButton = page.getByTestId('create-new-issue')
    await test.expect(createNewIssueButton).toBeVisible()
    await memex.omnibar.focusAndEnterText('new issue title')
    await createNewIssueButton.click()

    await test
      .expect(page.getByRole('dialog').getByRole('textbox', {name: 'Add a title'}))
      .toHaveValue('new issue title')

    // expect the project picker to have the memex title prefilled also
    test.expect(page.getByRole('dialog').getByText(DefaultMemex.title, {exact: false}))
  })

  test('returns focus to the omnibar when the issue create dialog is closed', async ({memex, page}) => {
    await memex.navigateToStory('integrationTestsWithItems')
    await memex.omnibar.focusAndEnterText('#')
    // Select a repository
    await memex.omnibar.repositoryList.getRepositoryListItemLocator(1).click()

    await expect(memex.omnibar.issuePicker.ISSUE_PICKER_LIST).toBeVisible()
    const createNewIssueButton = page.getByTestId('create-new-issue')
    await expect(createNewIssueButton).toBeVisible()
    await createNewIssueButton.click()

    await expect(page.getByRole('dialog').getByRole('textbox', {name: 'Add a title'})).toBeVisible()

    await page.keyboard.press('Escape')
    await expect(memex.omnibar.INPUT).toBeFocused()
    await expect(memex.omnibar.issuePicker.ISSUE_PICKER_LIST).toBeVisible()
  })

  test('does not open create dialog if input is an issue or PR URL', async ({memex, page}) => {
    const draftIssueUrlTitle = 'https://github.com/github/github/issues/1'
    const draftPullUrlTitle = 'https://github.com/github/github/pull/1'
    await memex.navigateToStory('integrationTestsWithItems')

    // Normally the issue creator appears and a new row is not added, but in this case, we skip to adding the issue item to the table
    await memex.omnibar.focusAndEnterText(draftIssueUrlTitle)
    await page.keyboard.press('ArrowDown')
    await page.keyboard.press('Enter')

    await page.waitForSelector(`text=${draftIssueUrlTitle}`)
    await waitForRowCount(page, 9)

    await memex.omnibar.focusAndEnterText(draftPullUrlTitle)
    await page.keyboard.press('ArrowDown')
    await page.keyboard.press('Enter')

    await page.waitForSelector(`text=${draftPullUrlTitle}`)
    await waitForRowCount(page, 10)
  })
})
