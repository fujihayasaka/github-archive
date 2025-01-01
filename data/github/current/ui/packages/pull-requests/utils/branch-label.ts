export function getBaseBranchText(
  baseBranch: string,
  baseRepositoryOwnerLogin: string,
  headRepositoryOwnerLogin?: string,
) {
  if (headRepositoryOwnerLogin && headRepositoryOwnerLogin !== baseRepositoryOwnerLogin) {
    return `${baseRepositoryOwnerLogin}:${baseBranch}`
  } else {
    return baseBranch
  }
}

export function getHeadBranchText(
  baseRepositoryOwnerLogin: string,
  headRepositoryOwnerLogin: string,
  headRepositoryName: string,
  headBranch: string,
  isInAdvisoryRepo?: boolean,
) {
  if (!headRepositoryOwnerLogin) {
    return 'unknown repository'
  }

  const isCrossRepo = !!headRepositoryOwnerLogin && headRepositoryOwnerLogin !== baseRepositoryOwnerLogin
  const isAdvisoryRepo = isInAdvisoryRepo && !!headRepositoryName

  switch (true) {
    case isCrossRepo && isAdvisoryRepo:
      return `${headRepositoryOwnerLogin}/${headRepositoryName}:${headBranch}`
    case isCrossRepo:
      return `${headRepositoryOwnerLogin}:${headBranch}`
    case isAdvisoryRepo:
      return `${headRepositoryName}:${headBranch}`
    default:
      return headBranch
  }
}
