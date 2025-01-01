export const VALUES = {
  repositoriesPreloadCount: 5,
  localStorageMetadataKeys: {
    issueLabels: (prefix: string) => `${prefix}.create-issue-labels`,
    issueAssignees: (prefix: string) => `${prefix}.create-issue-assignees`,
    issueMilestone: (prefix: string) => `${prefix}.create-issue-milestone`,
    issueProjects: (prefix: string) => `${prefix}.create-issue-projects`,
    issueIssueType: (prefix: string) => `${prefix}.create-issue-type`,
  },
  localStorageKeys: {
    issueCreateMore: (prefix: string) => `${prefix}.create-issue-create-more`,
    issueRepoId: (prefix: string) => `${prefix}.create-issue-repo-id`,
    issueTemplateId: (prefix: string) => `${prefix}.create-issue-template-id`,
  },
  localTitleAndBodyStorageKeys: {
    issueTitle: (prefix: string) => `${prefix}.create-issue-title`,
    issueBody: (prefix: string) => `${prefix}.create-issue-body`,
  },
  storageKeyPrefixes: {
    defaultFallback: 'hyperlist',
    globalAdd: 'issue-global-add',
  },
}

export function storageKeys(prefix: string) {
  return Object.values({
    ...VALUES.localStorageKeys,
    ...VALUES.localStorageMetadataKeys,
    ...VALUES.localTitleAndBodyStorageKeys,
  }).map(s => s(prefix))
}

export function storageMetadataKeys(prefix: string) {
  return Object.values(VALUES.localStorageMetadataKeys).map(s => s(prefix))
}

export function storageTitleAndBodyKeys(prefix: string) {
  return Object.values(VALUES.localTitleAndBodyStorageKeys).map(s => s(prefix))
}

// Values that we want to show the confirmation dialog for if they're not empty
const discardConfirmationStorageKeys = {
  title: VALUES.localTitleAndBodyStorageKeys.issueTitle,
  body: VALUES.localTitleAndBodyStorageKeys.issueBody,
}

export function discardStorageKeys(prefix: string) {
  return Object.values(discardConfirmationStorageKeys).map(s => s(prefix))
}
