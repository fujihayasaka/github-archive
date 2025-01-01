import type {RepositoryPickerRepositoryIssueTemplates$data} from '@github-ui/item-picker/RepositoryPickerRepositoryIssueTemplates.graphql'
import {repoHasAvailableTemplates, getPreselectedTemplate} from '../model'

type buildTemplatesProps = {
  hasTemplates?: boolean
  hasForms?: boolean
  hasSecurityPolicy?: boolean
  hasContactLinks?: boolean
  addUndefinedRecords?: boolean
}

function buildTemplates({
  hasTemplates = false,
  hasForms = false,
  hasSecurityPolicy = false,
  hasContactLinks = false,
  addUndefinedRecords = false,
}: buildTemplatesProps): RepositoryPickerRepositoryIssueTemplates$data {
  const issueTemplates = [{filename: 'template', name: 'Template', __typename: 'IssueTemplate'}]
  const issueForms = [{filename: 'form', name: 'Form', __typename: 'IssueForm'}]
  const contactLinks = [{name: 'link', __typename: 'RepositoryContactLink'}]
  if (addUndefinedRecords) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    issueTemplates.unshift(undefined as any)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    issueForms.unshift(undefined as any)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    contactLinks.unshift(undefined as any)
  }
  return {
    issueTemplates: hasTemplates ? issueTemplates : null,
    issueForms: hasForms ? issueForms : null,
    contactLinks: hasContactLinks ? contactLinks : null,
    isSecurityPolicyEnabled: hasSecurityPolicy,
  } as RepositoryPickerRepositoryIssueTemplates$data
}

test('`repoHasAvailableTemplates` correctly returns based on input', () => {
  expect(repoHasAvailableTemplates(null)).toBe(false)
  expect(repoHasAvailableTemplates(buildTemplates({hasTemplates: true}))).toBe(true)
  expect(repoHasAvailableTemplates(buildTemplates({hasForms: true}))).toBe(true)
  expect(repoHasAvailableTemplates(buildTemplates({hasSecurityPolicy: true}))).toBe(false)
  expect(repoHasAvailableTemplates(buildTemplates({hasContactLinks: true}))).toBe(true)
})

describe('`getPreselectedTemplate`', () => {
  test('returns undefined for empty templates and no arguments', () => {
    const templates = buildTemplates({})
    expect(getPreselectedTemplate({templates})).toBeUndefined()
  })

  test('returns the correct template based on `templateFileName`', () => {
    const templates = buildTemplates({hasTemplates: true})
    const issueCreateArguments = {templateFileName: 'template'}
    const result = getPreselectedTemplate({templates, issueCreateArguments})
    expect(result).toBeDefined()
    expect(result?.fileName).toBe('template')
  })

  test('is robust when presented with undefined records', () => {
    const templates = buildTemplates({hasTemplates: true, addUndefinedRecords: true})
    const issueCreateArguments = {templateFileName: 'template'}
    const result = getPreselectedTemplate({templates, issueCreateArguments})
    expect(result).toBeDefined()
    expect(result?.fileName).toBe('template')
  })
})
