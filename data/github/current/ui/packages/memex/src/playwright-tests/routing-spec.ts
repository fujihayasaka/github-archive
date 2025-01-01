import {expect} from '@playwright/test'

import {test} from './fixtures/test-extended'
import {mustFind} from './helpers/dom/assertions'
import {_} from './helpers/dom/selectors'

test.describe('Routing', () => {
  test.describe('Settings page', () => {
    test('User with admin permission can access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestSettingsPage', {
        testIdToAwait: 'settings-side-nav',
        viewerPrivileges: {
          viewerRole: 'admin',
        },
      })

      await expect(page.getByRole('heading', {name: 'Project settings'})).toBeVisible()
    })
    test('User with write permission can access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestSettingsPage', {
        testIdToAwait: 'settings-side-nav',
        viewerPrivileges: {
          viewerRole: 'write',
        },
      })

      await expect(page.getByRole('heading', {name: 'Project settings'})).toBeVisible()
    })
    test('User with read permission can not access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestSettingsPage', {
        testIdToAwait: '404-page',
        viewerPrivileges: {
          viewerRole: 'read',
        },
      })

      await mustFind(page, _('404-page'))
    })
  })

  test.describe('Settings field page', () => {
    test('User with admin permission can access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestSettingsFieldPage', {
        testIdToAwait: 'settings-side-nav',
        viewerPrivileges: {
          viewerRole: 'admin',
        },
      })

      await expect(page.getByRole('heading', {name: 'Status field settings'})).toBeVisible()
    })
    test('User with write permission can access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestSettingsFieldPage', {
        testIdToAwait: 'settings-side-nav',
        viewerPrivileges: {
          viewerRole: 'write',
        },
      })

      await expect(page.getByRole('heading', {name: 'Status field settings'})).toBeVisible()
    })
    test('User with read permission can not access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestSettingsFieldPage', {
        testIdToAwait: '404-page',
        viewerPrivileges: {
          viewerRole: 'read',
        },
      })

      await mustFind(page, _('404-page'))
    })
  })

  test.describe('Settings access page', () => {
    test('User with admin permission can access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestAccessSettingsPage', {
        testIdToAwait: 'access-settings',
      })

      await expect(page.getByRole('heading', {name: 'Who has access'})).toBeVisible()
    })
    test('User with write permission can not access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestAccessSettingsPage', {
        testIdToAwait: '404-page',
        viewerPrivileges: {
          viewerRole: 'write',
        },
      })

      await mustFind(page, _('404-page'))
    })
    test('User with read permission can not access', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestAccessSettingsPage', {
        testIdToAwait: '404-page',
        viewerPrivileges: {
          viewerRole: 'read',
        },
      })

      await mustFind(page, _('404-page'))
    })
  })
})
