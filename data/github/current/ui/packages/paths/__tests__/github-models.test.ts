import {
  modelsCatalogPath,
  modelFeedbackPath,
  modelPath,
  modelPlaygroundPath,
  modelPromptPath,
  organizationSettingsModelsAccessPolicyPath,
  repoModelsPath,
  repoModelsPromptPath,
} from '../github-models'
import type {Repository} from '../types'

const modelRegistry = 'openai'
const modelName = 'gpt-4o'

describe('github_models paths', () => {
  describe('modelFeedbackPath', () => {
    test('returns the relative feedback url for a model', () => {
      const model = {registry: modelRegistry, name: modelName}
      expect(modelFeedbackPath(model)).toEqual(`/marketplace/models/${modelRegistry}/${modelName}/feedback`)
    })
  })

  describe('organizationSettingsModelsAccessPolicyPath', () => {
    test('returns the relative path for the org Models access policy page', () => {
      expect(organizationSettingsModelsAccessPolicyPath({org: 'someOrg'})).toEqual(
        '/organizations/someOrg/settings/models/access-policy',
      )
    })

    test('works when given a URL parameter for building a template string', () => {
      expect(organizationSettingsModelsAccessPolicyPath({org: ':org'})).toEqual(
        '/organizations/:org/settings/models/access-policy',
      )
    })
  })

  describe('modelPromptPath', () => {
    test('returns the relative prompt url for a model', () => {
      const model = {registry: modelRegistry, name: modelName}
      expect(modelPromptPath(model)).toEqual(`/marketplace/models/${modelRegistry}/${modelName}/prompt`)
    })

    test('includes commit and line range details when specified', () => {
      const commit = 'abcd12345face398f34f3b7b7db142a0724fa958'
      const filePath = 'test.txt'
      const repoOwner = 'someUser'
      const repoName = 'some-nice-repo'
      const beginLine = 15
      const endLine = 30
      const result = modelPromptPath({
        registry: modelRegistry,
        name: modelName,
        commit,
        filePath,
        repoOwner,
        repoName,
        beginLine,
        endLine,
      })
      expect(result).toEqual(
        `/marketplace/models/${modelRegistry}/${modelName}/prompt?c=${commit}&path=${filePath}&l=${repoOwner}&n=${repoName}&lines=${beginLine}-${endLine}`,
      )
    })

    test('expands line range when a single line is given', () => {
      const lineNumber = 42
      const result = modelPromptPath({
        registry: modelRegistry,
        name: modelName,
        beginLine: lineNumber,
        endLine: lineNumber,
      })
      expect(result).toEqual(
        `/marketplace/models/${modelRegistry}/${modelName}/prompt?lines=${lineNumber - 10}-${lineNumber + 10}`,
      )
    })
  })

  describe('modelsCatalogPath', () => {
    test('handles multi-word category', () => {
      expect(modelsCatalogPath({category: 'low latency'})).toEqual('/marketplace?type=models&category=low+latency')
    })

    test('handles multi-word task', () => {
      expect(modelsCatalogPath({task: 'chat completion'})).toEqual('/marketplace?type=models&task=chat-completion')
    })

    test('handles multiple filters', () => {
      expect(modelsCatalogPath({category: 'large context', task: 'embeddings'})).toEqual(
        '/marketplace?type=models&category=large+context&task=embeddings',
      )
    })

    test('returns /catalog path when no filters are given', () => {
      expect(modelsCatalogPath()).toEqual('/marketplace/models/catalog')
    })

    test('handles publisher', () => {
      expect(modelsCatalogPath({publisher: 'foo'})).toEqual(`/marketplace?type=models&publisher=foo`)
    })
  })

  describe('modelPath', () => {
    test('returns the relative model url', () => {
      const model = {registry: modelRegistry, name: modelName}
      expect(modelPath(model)).toEqual(`/marketplace/models/${modelRegistry}/${modelName}`)
    })
  })

  describe('modelPlaygroundPath', () => {
    test('returns the relative playground url for a model', () => {
      const model = {registry: modelRegistry, name: modelName}
      expect(modelPlaygroundPath(model)).toEqual(`/marketplace/models/${modelRegistry}/${modelName}/playground`)
    })
  })

  describe('repoModelsPath', () => {
    test('returns the relative repo models url', () => {
      expect(
        repoModelsPath({
          repo: {name: 'repo-name', ownerLogin: 'owner-login'} as Repository,
        }),
      ).toEqual('/owner-login/repo-name/models')
    })

    test('returns the relative repo models url for prompts', () => {
      expect(
        repoModelsPath({
          repo: {name: 'repo-name', ownerLogin: 'owner-login'} as Repository,
          action: 'prompts',
        }),
      ).toEqual('/owner-login/repo-name/models/prompts')
    })
  })
})

describe('repoModelsPromptPath', () => {
  test('returns the relative repo models prompt url edit', () => {
    expect(
      repoModelsPromptPath({
        repo: {name: 'repo-name', ownerLogin: 'owner-login'} as Repository,
        commitish: 'main',
        action: 'edit',
      }),
    ).toEqual('/owner-login/repo-name/models/prompt/edit/main')
  })

  test('returns the relative repo models prompt url edit with path', () => {
    expect(
      repoModelsPromptPath({
        repo: {name: 'repo-name', ownerLogin: 'owner-login'} as Repository,
        commitish: 'main',
        action: 'edit',
        path: 'test.prompt.md',
      }),
    ).toEqual('/owner-login/repo-name/models/prompt/edit/main/test.prompt.md')
  })

  test('returns the relative repo models prompt url compare', () => {
    expect(
      repoModelsPromptPath({
        repo: {name: 'repo-name', ownerLogin: 'owner-login'} as Repository,
        commitish: 'main',
        action: 'compare',
      }),
    ).toEqual('/owner-login/repo-name/models/prompt/compare/main')
  })

  test('returns the relative repo models prompt url compare with path', () => {
    expect(
      repoModelsPromptPath({
        repo: {name: 'repo-name', ownerLogin: 'owner-login'} as Repository,
        commitish: 'main',
        action: 'compare',
        path: 'test.prompt.md',
      }),
    ).toEqual('/owner-login/repo-name/models/prompt/compare/main/test.prompt.md')
  })
})
