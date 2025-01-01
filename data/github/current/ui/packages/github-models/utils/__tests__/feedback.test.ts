import {sendFeedback} from '../feedback'
import {mockModel, mockFeedbackState} from '../../routes/playground/__tests__/mocks'

const mockVerifiedFetchJSON = jest.fn()
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
}))

describe('sendFeedback', () => {
  it('returns response from feedback endpoint', async () => {
    const expectedResponse = {ok: true, json: () => ({})}

    mockVerifiedFetchJSON.mockResolvedValue(expectedResponse)

    await expect(sendFeedback({model: mockModel, feedback: mockFeedbackState})).resolves.toEqual(expectedResponse)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/marketplace/models/${mockModel.registry}/${mockModel.name}/feedback`,
      {
        method: 'POST',
        body: {
          feedback: mockFeedbackState,
        },
      },
    )
  })

  it('throws an error if response from feedback endpoint is not ok', async () => {
    const errorResponse = new Error('Failed to submit feedback')

    mockVerifiedFetchJSON.mockRejectedValue(errorResponse)

    await expect(sendFeedback({model: mockModel, feedback: mockFeedbackState})).rejects.toThrow(errorResponse)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/marketplace/models/${mockModel.registry}/${mockModel.name}/feedback`,
      {
        method: 'POST',
        body: {
          feedback: mockFeedbackState,
        },
      },
    )
  })
})
