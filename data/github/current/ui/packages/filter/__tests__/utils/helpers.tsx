import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'
import {hasMatch} from 'fzy.js'

import {TIME_RANGE_VALUES} from '../../constants/dynamic-filter-values'
import {issues, issueSuggestions, labels, labelSuggestions, users, userSuggestions} from '../../mocks'
import {languages, languageSuggestions} from '../../mocks/languages'
import {milestones, milestoneSuggestions} from '../../mocks/milestones'
import {orgs, orgSuggestions} from '../../mocks/orgs'
import {projects, projectSuggestions} from '../../mocks/projects'
import {repositories, repositorySuggestions} from '../../mocks/repositories'
import {teams, teamSuggestions} from '../../mocks/teams'
import {setupExpectedAsyncErrorHandler} from '../../test-utils'

const globalFetch = global.fetch
const userEvent = setupUserEvent()

export function setupAsyncErrorHandler() {
  beforeEach(() => {
    setupExpectedAsyncErrorHandler()
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })
}

export function setupProjectsMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            projects: filterValue
              ? projects.filter(p => {
                  return hasMatch(filterValue, p.title) || hasMatch(filterValue, p.value)
                })
              : projectSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupUsersMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            users: filterValue
              ? users.filter(u => {
                  return (
                    filterValue === '@me' || hasMatch(filterValue, u.login) || (u.name && hasMatch(filterValue, u.name))
                  )
                })
              : userSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupIssuesMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            issues: filterValue
              ? issues.filter(i => {
                  return hasMatch(filterValue, i.title) || hasMatch(filterValue, i.nwoReference)
                })
              : issueSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupLabelsMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            labels: filterValue
              ? labels.filter(l => {
                  return hasMatch(filterValue, l.name)
                })
              : labelSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupLanguageMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            languages: filterValue
              ? languages.filter(l => {
                  return hasMatch(filterValue, l.name)
                })
              : languageSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupMilestoneMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            milestones: filterValue
              ? milestones.filter(m => {
                  return hasMatch(filterValue, m.title) || hasMatch(filterValue, m.value)
                })
              : milestoneSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupOrgsMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            orgs: filterValue
              ? orgs.filter(r => {
                  return hasMatch(filterValue, r.name)
                })
              : orgSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupRepositoriesMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            repositories: filterValue
              ? repositories.filter(r => {
                  return hasMatch(filterValue, r.name) || (r.nameWithOwner && hasMatch(filterValue, r.nameWithOwner))
                })
              : repositorySuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export function setupTeamsMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            teams: filterValue
              ? teams.filter(team => {
                  return hasMatch(filterValue, team.name) || hasMatch(filterValue, team.combinedSlug)
                })
              : teamSuggestions,
          }),
      })
    }) as jest.Mock
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

export async function appendToFilterAndRenderAsyncSuggestions(text: string, selectionStart?: number) {
  screen.getByRole('combobox').focus()

  if (selectionStart !== undefined) {
    const input: HTMLInputElement = screen.getByRole('combobox')
    input.setSelectionRange(selectionStart, selectionStart)
  }

  await userEvent.keyboard(text)
}

export async function selectSuggestion(value: string) {
  const options = await getSuggestions()
  const index = options.findIndex(suggestion => suggestion?.toLowerCase().includes(value.toLowerCase()))

  if (index < 0) throw new Error(`Suggestion "${value}" not found in list: ${options.join(', ')}`)

  await userEvent.keyboard(`{ArrowDown>${index + 1}}`)
  await userEvent.keyboard('{Enter}')
}

async function getSuggestions() {
  let suggestions: HTMLElement[] = []

  await waitFor(() => {
    suggestions = within(screen.getByTestId('filter-results')).queryAllByRole('option')
    expect(suggestions).not.toHaveLength(0)
  })

  return suggestions.map(suggestion => suggestion.textContent)
}

export async function expectDateSuggestionsToMatchSnapshot() {
  const suggestions = await getSuggestions()
  expect(suggestions.pop()).toBe(TIME_RANGE_VALUES[5]?.displayName)
  expect(suggestions).toMatchSnapshot()
}

export async function expectSuggestionsToMatchSnapshot() {
  expect(await getSuggestions()).toMatchSnapshot()
}

export async function expectSuggestionsToBeEmpty() {
  await waitFor(() => {
    const option = within(screen.getByTestId('filter-results')).queryByRole('option')
    expect(option).not.toBeInTheDocument()
  })
}

export async function expectFilterValueToBe(value: string) {
  await waitFor(() => {
    expect(screen.getByRole('combobox')).toHaveValue(value)
  })
}

export async function expectErrorMessage(key: string, value: string) {
  await waitFor(() => {
    expect(screen.getByTestId('validation-error-count')).toHaveTextContent('Filter contains 1 issue:')
  })
  expect(screen.getByTestId('validation-error-list')).toHaveTextContent(`Invalid value ${value} for ${key}`)
  expect(screen.getByTestId('filter-input')).toHaveAttribute('aria-describedby', 'test-filter-bar-validation-message')
}

export async function expectEmptyValueMessage(key: string) {
  await waitFor(() => {
    expect(screen.getByTestId('validation-error-count')).toHaveTextContent('Filter contains 1 issue:')
  })
  expect(screen.getByTestId('validation-error-list')).toHaveTextContent(`Empty value for ${key}`)
  expect(screen.getByTestId('filter-input')).toHaveAttribute('aria-describedby', 'test-filter-bar-validation-message')
}

export function expectNoErrorMessage() {
  expect(screen.queryByTestId('validation-error-count')).not.toBeInTheDocument()
  expect(screen.queryByTestId('validation-error-list')).not.toBeInTheDocument()
}
