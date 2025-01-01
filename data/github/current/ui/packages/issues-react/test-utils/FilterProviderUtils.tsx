import {waitFor, within, screen} from '@testing-library/react'
import {hasMatch} from 'fzy.js'
import {users, copilotBot} from './mock-data'
import {setupUserEvent} from '@github-ui/react-core/test-utils'

const globalFetch = global.fetch

export function setupUsersWithCopilotBotMockApi() {
  beforeAll(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            users: filterValue
              ? [...users, copilotBot].filter(u => {
                  return (
                    filterValue === '@me' || hasMatch(filterValue, u.login) || (u.name && hasMatch(filterValue, u.name))
                  )
                })
              : [...users, copilotBot],
          }),
      })
    }) as jest.Mock
  })

  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation((message: string) => {
      // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
      // * any errors that are not related to the async nature of the component.
      if (!message.includes?.('wrapped in act(')) {
        // eslint-disable-next-line no-console
        console.error(message)
      }
    })
  })

  afterAll(() => {
    global.fetch = globalFetch
  })
}

const userEvent = setupUserEvent()

export async function updateFilterValue(filterValue: string) {
  screen.getByRole('combobox').focus()

  await userEvent.paste(filterValue)

  await expectFilterValueToBe(filterValue)
}

export async function expectFilterValueToBe(filterValue: string) {
  await waitFor(() => {
    expect(screen.getByRole('combobox')).toHaveValue(filterValue)
  })
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
