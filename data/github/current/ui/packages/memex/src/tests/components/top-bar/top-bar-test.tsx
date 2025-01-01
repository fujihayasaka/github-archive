import {render, screen} from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import type {Owner} from '../../../client/api/common-contracts'
import {Role} from '../../../client/api/common-contracts'
import {TopBar} from '../../../client/components/top-bar'
import {MemexTitle} from '../../../client/components/top-bar/memex-title'
import {useEnabledFeatures} from '../../../client/hooks/use-enabled-features'
import {memexFactory} from '../../factories/memexes/memex-factory'
import {mockUseHasColumnData} from '../../mocks/hooks/use-has-column-data'
import {asMockHook} from '../../mocks/stub-utilities'
import {createTestEnvironment, TestAppContainer} from '../../test-app-wrapper'

jest.mock('../../../client/hooks/use-enabled-features')

const templateOwner = {
  id: 1,
  login: 'github',
  name: 'GitHub',
  avatarUrl: 'https://foo.bar/avatar.png',
  type: 'organization',
} satisfies Owner

describe('TopBar', () => {
  beforeEach(() => {
    mockUseHasColumnData()
    asMockHook(useEnabledFeatures).mockReturnValue({})
  })

  describe('Memex Title', () => {
    it('should render the project title', () => {
      const memex = memexFactory.build({titleHtml: 'My Memex'})
      createTestEnvironment({
        'memex-data': memex,
      })

      render(
        <TestAppContainer>
          <TopBar isProjectPath>
            <MemexTitle />
          </TopBar>
        </TestAppContainer>,
      )

      expect(screen.getByRole('heading', {name: 'My Memex'})).toBeInTheDocument()
    })
  })

  describe('Beta pill', () => {
    it('should render the beta pill if memex_table_without_limits is enabled', () => {
      asMockHook(useEnabledFeatures).mockReturnValue({memex_table_without_limits: true})
      const memex = memexFactory.build({titleHtml: 'My Memex'})
      createTestEnvironment({
        'memex-data': memex,
      })

      render(
        <TestAppContainer>
          <TopBar isProjectPath>
            <MemexTitle />
          </TopBar>
        </TestAppContainer>,
      )

      expect(screen.getByTestId('memex_without_limits_beta_label')).toBeInTheDocument()
    })

    it('should not render the beta pill if memex_table_without_limits is disabled', () => {
      const memex = memexFactory.build({titleHtml: 'My Memex'})
      createTestEnvironment({
        'memex-data': memex,
      })

      render(
        <TestAppContainer>
          <TopBar isProjectPath>
            <MemexTitle />
          </TopBar>
        </TestAppContainer>,
      )

      expect(screen.queryByTestId('memex_without_limits_beta_label')).not.toBeInTheDocument()
    })

    it('should render the beta pill if the kill switch is enabled', () => {
      const memex = memexFactory.build({titleHtml: 'My Memex'})
      createTestEnvironment({
        'memex-data': memex,
        'memex-service': {betaSignupBanner: 'hidden', killSwitchEnabled: true},
      })

      render(
        <TestAppContainer>
          <TopBar isProjectPath>
            <MemexTitle />
          </TopBar>
        </TestAppContainer>,
      )

      expect(screen.getByTestId('memex_without_limits_beta_label')).toBeInTheDocument()
    })
  })

  describe('Copy permissions', () => {
    const loggedInUser = {
      id: 1,
      login: 'monalisa',
      name: 'monalisa',
      avatarUrl: 'https://github.com/github.png',
      global_relay_id: 'ABC123',
      isSpammy: false,
      paste_url_link_as_plain_text: false,
    }

    async function renderTopBarWithPrivileges(privileges: {role: Role; canCopy: boolean; canCopyAsTemplate: boolean}) {
      const user = userEvent.setup()
      const memex = memexFactory.build({titleHtml: 'My Memex'})
      createTestEnvironment({
        'memex-data': memex,
        'logged-in-user': loggedInUser,
        'memex-viewer-privileges': {
          canChangeProjectVisibility: false,
          ...privileges,
        },
      })
      asMockHook(useEnabledFeatures).mockReturnValue({})

      render(
        <TestAppContainer>
          <TopBar isProjectPath>
            <MemexTitle />
          </TopBar>
        </TestAppContainer>,
      )

      await user.click(screen.getByTestId('project-menu-button'))
    }

    it('shows "Make a copy" when canCopy is true', async () => {
      await renderTopBarWithPrivileges({role: Role.Write, canCopy: true, canCopyAsTemplate: false})
      expect(screen.getByTestId('copy-project-button')).toBeInTheDocument()
    })

    it('hides "Make a copy" when canCopy is false (Read role)', async () => {
      await renderTopBarWithPrivileges({role: Role.Read, canCopy: false, canCopyAsTemplate: false})
      expect(screen.queryByTestId('copy-project-button')).not.toBeInTheDocument()
    })

    it('hides "Make a copy" when canCopy is false (Write role)', async () => {
      await renderTopBarWithPrivileges({role: Role.Write, canCopy: false, canCopyAsTemplate: false})
      expect(screen.queryByTestId('copy-project-button')).not.toBeInTheDocument()
    })

    it('shows "Copy as template" when canCopyAsTemplate is true', async () => {
      await renderTopBarWithPrivileges({role: Role.Write, canCopy: true, canCopyAsTemplate: true})
      expect(screen.getByTestId('copy-as-template-button')).toBeInTheDocument()
    })

    it('hides "Copy as template" when canCopyAsTemplate is false', async () => {
      await renderTopBarWithPrivileges({role: Role.Write, canCopy: true, canCopyAsTemplate: false})
      expect(screen.queryByTestId('copy-as-template-button')).not.toBeInTheDocument()
    })
  })

  describe('Use this template', () => {
    it('should not show use template button on non-templates', () => {
      const memex = memexFactory.build({titleHtml: 'My Memex', isTemplate: false})
      createTestEnvironment({
        'memex-data': memex,
        'memex-owner': templateOwner,
      })

      render(
        <TestAppContainer>
          <TopBar isProjectPath>
            <MemexTitle />
          </TopBar>
        </TestAppContainer>,
      )

      expect(screen.queryByRole('button', {name: 'Use this template'})).not.toBeInTheDocument()
    })

    it('shows use template button on templates', () => {
      const memex = memexFactory.build({titleHtml: 'My Memex', isTemplate: true, templateId: 1})
      createTestEnvironment({
        'memex-data': memex,
        'memex-owner': templateOwner,
      })

      render(
        <TestAppContainer>
          <TopBar isProjectPath>
            <MemexTitle />
          </TopBar>
        </TestAppContainer>,
      )

      expect(screen.getByRole('button', {name: 'Use this template'})).toBeInTheDocument()
    })
  })
})
