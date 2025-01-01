import {act, render, screen} from '@testing-library/react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {RunnerPublicIpCheckbox} from '../RunnerPublicIpCheckbox'

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

beforeEach(() => {
  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        usedIpCount: 0,
        totalIpCount: 10,
      }
    },
  })
})

describe('RunnerPublicIpCheckbox', () => {
  test('renders correctly for an empty form', async () => {
    render(
      <RunnerPublicIpCheckbox
        checked={false}
        onChange={jest.fn()}
        isPublicIpAllowed
        publicIpInfoPath="path/to/public_ip_info"
      />,
    )

    const publicIpCheckbox = screen.getByTestId('runner-public-ip-checkbox')
    expect(publicIpCheckbox).not.toBeChecked()
    expect(publicIpCheckbox).toBeDisabled()

    const spinner = screen.getByTestId('runner-public-ip-spinner')
    expect(spinner).toBeInTheDocument()

    await act(() => {
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`path/to/public_ip_info`)
    })
  })

  test.each([
    [0, 10, false, false, true], //
    [0, 10, false, true, false], //
    [0, 10, true, false, true], //
    [0, 10, true, true, false], //
    [10, 10, false, false, true], //
    [10, 10, false, true, true],
    [10, 10, true, false, true], //
    [10, 10, true, true, false],
  ])(
    `after fetching details (usedIpCount=%i, totalIpCount=%i, runnerHasPublicIp=%s, isPublicIpAllowed=%s): checkbox is disabled=%s`,
    async (usedIpCount, totalIpCount, runnerHasPublicIp, isPublicIpAllowed, expectedDisabled) => {
      mockVerifiedFetchJSON.mockResolvedValue({
        ok: true,
        statusText: 'OK',
        json: async () => {
          return {
            usedIpCount,
            totalIpCount,
          }
        },
      })

      render(
        <RunnerPublicIpCheckbox
          checked={false}
          onChange={jest.fn()}
          isPublicIpAllowed={isPublicIpAllowed}
          runnerHasPublicIp={runnerHasPublicIp}
          publicIpInfoPath="path/to/public_ip_info"
        />,
      )

      // Resolve the fetch
      await act(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalled()
      })

      /* eslint eslint-comments/no-use: off */
      /* eslint-disable jest/no-conditional-expect */
      const checkbox = screen.getByTestId('runner-public-ip-checkbox')
      if (expectedDisabled) {
        expect(checkbox).toBeDisabled()
      } else {
        expect(checkbox).not.toBeDisabled()
      }
      /* eslint-enable jest/no-conditional-expect */

      // Ensure we're testing something due to the conditional
      expect.assertions(2)
    },
  )
})
