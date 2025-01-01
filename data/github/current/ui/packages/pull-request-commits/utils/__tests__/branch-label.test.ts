import {getBaseBranchText, getHeadBranchText} from '../branch-label'

describe('getBaseBranchText', () => {
  it('returns the base branch when the head repository owner login is the same as the base repository owner login', () => {
    const baseBranch = 'main'
    const baseRepositoryOwnerLogin = 'monalisa'
    const headRepositoryOwnerLogin = 'monalisa'

    const result = getBaseBranchText(baseBranch, baseRepositoryOwnerLogin, headRepositoryOwnerLogin)

    expect(result).toEqual(baseBranch)
  })

  it('returns the base branch with the base repository owner login when the head repository owner login is different from the base repository owner login', () => {
    const baseBranch = 'main'
    const baseRepositoryOwnerLogin = 'monalisa'
    const headRepositoryOwnerLogin = 'hubot'

    const result = getBaseBranchText(baseBranch, baseRepositoryOwnerLogin, headRepositoryOwnerLogin)

    expect(result).toEqual('monalisa:main')
  })
})

describe('getHeadBranchText', () => {
  it('returns unknown repository when the head repository owner login is not defined', () => {
    const baseRepositoryOwner = 'monalisa'
    const headRepositoryOwner = ''
    const headRepositoryName = 'monalisa'
    const headBranch = 'main'

    const result = getHeadBranchText(baseRepositoryOwner, headRepositoryOwner, headRepositoryName, headBranch)

    expect(result).toEqual('unknown repository')
  })

  describe('cross repo', () => {
    it('repository is an advisory repo', () => {
      const baseRepositoryOwner = 'monalisa'
      const headRepositoryOwner = 'hubot'
      const headRepositoryName = 'monalisa'
      const headBranch = 'main'
      const isInAdvisoryRepo = true

      const result = getHeadBranchText(
        baseRepositoryOwner,
        headRepositoryOwner,
        headRepositoryName,
        headBranch,
        isInAdvisoryRepo,
      )

      expect(result).toEqual('hubot/monalisa:main')
    })

    it('repository is not an advisory repo - default fork behavior', () => {
      const baseRepositoryOwner = 'monalisa'
      const headRepositoryOwner = 'hubot'
      const headRepositoryName = 'monalisa'
      const headBranch = 'main'
      const isInAdvisoryRepo = false

      const result = getHeadBranchText(
        baseRepositoryOwner,
        headRepositoryOwner,
        headRepositoryName,
        headBranch,
        isInAdvisoryRepo,
      )

      expect(result).toEqual('hubot:main')
    })
  })

  describe('same repo', () => {
    it('repository is an advisory repo', () => {
      const baseRepositoryOwner = 'monalisa'
      const headRepositoryOwner = 'monalisa'
      const headRepositoryName = 'monalisa'
      const headBranch = 'main'
      const isInAdvisoryRepo = true

      const result = getHeadBranchText(
        baseRepositoryOwner,
        headRepositoryOwner,
        headRepositoryName,
        headBranch,
        isInAdvisoryRepo,
      )

      expect(result).toEqual('monalisa:main')
    })

    it('repository is not an advisory repo - default behavior', () => {
      const baseRepositoryOwner = 'monalisa'
      const headRepositoryOwner = 'monalisa'
      const headRepositoryName = 'monalisa'
      const headBranch = 'main'
      const isInAdvisoryRepo = false

      const result = getHeadBranchText(
        baseRepositoryOwner,
        headRepositoryOwner,
        headRepositoryName,
        headBranch,
        isInAdvisoryRepo,
      )

      expect(result).toEqual('main')
    })
  })
})
