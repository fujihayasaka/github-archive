import {render} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor, within} from '@testing-library/react'
import {useState} from 'react'

import {BusinessTeamNameInput} from '../BusinessTeamNameInput'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

const mockVerifiedFetch = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

beforeEach(() => {
  mockVerifiedFetch.mockClear()
})

describe('BusinessTeamNameInput', () => {
  jest.useFakeTimers()

  test('fires check on team name input', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      json: async () => {
        return {
          team: 'secops',
        }
      },
    })
    const {user} = render(<InputWrapper />)

    act(() => {
      user.type(getInput(), 'secops')
    })
    const mentionText = await screen.findByText(/Mention this team in conversations as/)
    const strongText = within(mentionText).getByText(/@github-inc\/secops/)

    expect(strongText).toBeInTheDocument()
    await waitFor(() => {
      expect(mockVerifiedFetch).toHaveBeenCalled()
    })
  })

  test('fires check on name change', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      json: async () => {
        return {
          team: 'tnt',
        }
      },
    })

    const {user} = render(<InputWrapper oldTeamName="secops" />)

    act(() => {
      user.type(getInput(), 'tnt')
    })

    const mentionText = await screen.findByText(/Mention this team in conversations as/)
    const strongText = within(mentionText).getByText(/@github-inc\/tnt/)
    expect(strongText).toBeInTheDocument()
    await waitFor(() => {
      expect(mockVerifiedFetch).toHaveBeenCalled()
    })
  })

  test('does not fire check when team name input is cleared', async () => {
    const {user} = render(<InputWrapper name="secops" />)

    act(() => {
      user.clear(getInput())
    })

    const message = await screen.findByText('New team name must not be blank')
    expect(message).toBeInTheDocument()
    expect(mockVerifiedFetch).not.toHaveBeenCalled()
  })

  test('displays error when team name is already taken', async () => {
    mockVerifiedFetch.mockResolvedValue({
      status: 422,
      ok: false,
      json: async () => {
        return {
          team: 'secops',
          error: 'is already taken',
        }
      },
    })

    const {user} = render(<InputWrapper />)

    act(() => {
      user.type(getInput(), 'secops')
    })
    const message = await screen.findByText(/is already taken/, {exact: false})
    const strongText = within(message).getByText(/secops/)
    expect(strongText).toBeInTheDocument()
    await waitFor(() => {
      expect(mockVerifiedFetch).toHaveBeenCalled()
    })
  })

  test('displays error when team name contains invalid characters', async () => {
    mockVerifiedFetch.mockResolvedValue({
      status: 422,
      ok: false,
      json: async () => {
        return {
          team: 'pumpkin enthusiasts 🎃',
          error: 'contains unsupported characters',
        }
      },
    })
    const {user} = render(<InputWrapper />)

    act(() => {
      user.type(getInput(), 'pumpkin enthusiasts 🎃')
    })
    const message = await screen.findByText(/contains unsupported characters/, {exact: false})
    const strongText = within(message).getByText(/pumpkin enthusiasts 🎃/)
    expect(strongText).toBeInTheDocument()
    await waitFor(() => {
      expect(mockVerifiedFetch).toHaveBeenCalled()
    })
  })
})

function getInput() {
  return screen.getByTestId('business-team-name-input')
}

function InputWrapper({
  name = '',
  businessSlug = 'github-inc',
  oldTeamName = '',
}: {
  name?: string
  businessSlug?: string
  oldTeamName?: string
}) {
  const [oldName] = useState(oldTeamName)
  const [teamName, setTeamName] = useState(name)

  return (
    <BusinessTeamNameInput
      businessSlug={businessSlug}
      businessTeamName={teamName}
      businessTeamSlug={oldName}
      onChange={setTeamName}
      onValidityChange={jest.fn()}
      readonly={false}
      hideBlankCheck={false}
      editMode={false}
    />
  )
}
