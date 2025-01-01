import {isFeatureEnabled} from '@github-ui/feature-flags'

import {mockSkill} from '../../test-utils/mock-client-skill'
import {CLIENT_SKILL_REGISTRY} from '../client-skills-registry'
import {registerSkillsForPath} from '../register-skills-for-path'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

jest.mock('../client-skills-registry', () => ({
  ...jest.requireActual('../client-skills-registry'),
}))

const mockedIsFeatureEnabled = jest.mocked(isFeatureEnabled)

describe('registerSkillsForPath', () => {
  it('should not register skills whose feature flag is not enabled', () => {
    const includeRegex = /.*/
    const testPath = '/foo'
    CLIENT_SKILL_REGISTRY['disabled-skill'] = {
      constructor: mockSkill(),
      featureFlag: 'disabled_feature',
      schema: {
        type: 'function',
        function: {
          name: 'disabled-skill',
          description: 'test description',
          parameters: {type: 'object', properties: {}},
        },
      },
      includePaths: [includeRegex],
    }
    // Make sure the reason it's excluded isn't the regex match
    expect(testPath).toMatch(includeRegex)
    const result = registerSkillsForPath(testPath)
    expect(result).toHaveLength(0)
  })

  it('should not register skills without an include or exclude path', () => {
    CLIENT_SKILL_REGISTRY['disabled-skill'] = {
      constructor: mockSkill(),
      schema: {
        type: 'function',
        function: {
          name: 'disabled-skill',
          description: 'test description',
          parameters: {type: 'object', properties: {}},
        },
      },
    }
    const testPath = '/foo'
    const result = registerSkillsForPath(testPath)
    expect(result).toHaveLength(0)
  })

  describe('dom skills', () => {
    it('should not register dom skills on settings paths', () => {
      mockedIsFeatureEnabled.mockReturnValue(true)

      expect(registerSkillsForPath('/settings/profile')).not.toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-dom',
          }),
        }),
      )

      expect(registerSkillsForPath('/settings/emails/new')).not.toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-dom',
          }),
        }),
      )
    })

    it('should register dom skills on non-settings paths', () => {
      mockedIsFeatureEnabled.mockReturnValue(true)
      expect(registerSkillsForPath('/')).toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-dom',
          }),
        }),
      )

      expect(registerSkillsForPath('/my-settings-repository/settings/')).toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-dom',
          }),
        }),
      )

      expect(registerSkillsForPath('/monalisa/smile/settings')).toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-dom',
          }),
        }),
      )
    })
  })

  describe('workspace skills', () => {
    it('should register skills on a workspace editor path', () => {
      mockedIsFeatureEnabled.mockReturnValue(true)
      expect(registerSkillsForPath('/monalisa/smile/pull/1/edit')).toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-local-workspace-file',
          }),
        }),
      )
    })

    it('should not register skills on any non-workspace editor path', () => {
      mockedIsFeatureEnabled.mockReturnValue(true)
      expect(registerSkillsForPath('/monalisa/smile/pull/1/files')).not.toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-local-workspace-file',
          }),
        }),
      )

      expect(registerSkillsForPath('/monalisa/smile/pull/1/commits')).not.toContainEqual(
        expect.objectContaining({
          function: expect.objectContaining({
            name: 'read-local-workspace-file',
          }),
        }),
      )
    })
  })
})
