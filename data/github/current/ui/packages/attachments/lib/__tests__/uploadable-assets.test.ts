import {verifiedFetch} from '@github-ui/verified-fetch'

import {mockPolicy, testFile} from '../test-utils'
import {complete, createPolicy, GenericServerError, uploadFile} from '../uploadable-assets'

jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn().mockName('verifiedFetch'),
}))
const mockVerifiedFetch = jest.mocked(verifiedFetch)

beforeEach(() => {
  jest.resetAllMocks()
})

describe('createPolicy', () => {
  test('create', async () => {
    const mockedPolicy = mockPolicy()
    mockVerifiedFetch.mockImplementationOnce(async () => Response.json(mockedPolicy))

    const policy = await createPolicy(
      {name: 'Test', content_type: 'image/png', size: '123'},
      '/some-url',
      new AbortController().signal,
    )

    expect(policy).toEqual(mockedPolicy)

    expect(mockVerifiedFetch).toHaveBeenCalledTimes(1)
    const req = mockVerifiedFetch.mock.lastCall![1]!
    expect(req.body).toBeInstanceOf(FormData)
    const form = req.body! as FormData
    expect(Object.fromEntries(form.entries())).toEqual({
      name: 'Test',
      content_type: 'image/png',
      size: '123',
    })
  })

  test('throws a GenericServerError on non 200 responses', async () => {
    mockVerifiedFetch.mockImplementationOnce(async () =>
      Response.json(
        {errors: ['error 1']},
        {
          status: 500,
        },
      ),
    )

    await expect(
      createPolicy({name: 'Test', content_type: 'image/png', size: '123'}, '/some-url', new AbortController().signal),
    ).rejects.toBeInstanceOf(GenericServerError)
  })

  test('if there is no asset_upload_url throw an error', async () => {
    mockVerifiedFetch.mockImplementationOnce(async () => {
      const policy = mockPolicy()
      // @ts-expect-error we are specifically not conforming to the type
      delete policy.asset_upload_url
      return Response.json(policy)
    })

    await expect(
      createPolicy({name: 'Test', content_type: 'image/png', size: '123'}, '/some-url', new AbortController().signal),
    ).rejects.toThrow(/missing asset upload URL/)
  })
})

describe('uploadFile', () => {
  test('can upload a file', async () => {
    const fetchSpy = jest.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response())

    const file = testFile()
    const result = await uploadFile(file, mockPolicy(), new AbortController().signal)

    expect(fetchSpy).toHaveBeenCalledTimes(1)
    expect(result).toBeUndefined()

    const req = fetchSpy.mock.lastCall![1]!
    expect(req.body).toBeInstanceOf(FormData)
    const form = req.body! as FormData
    expect(Object.fromEntries(form.entries())).toEqual({
      FORM_KEY: 'FORM_VALUE',
      file,
    })
  })

  test('if the response is not ok, throws an error', async () => {
    jest.spyOn(globalThis, 'fetch').mockImplementation(
      async () =>
        new Response('some failure', {
          status: 500,
        }),
    )

    await expect(uploadFile(testFile(), mockPolicy(), new AbortController().signal)).rejects.toThrow(/some failure/)
  })
})

describe('complete', () => {
  test('can complete', async () => {
    const mockedPolicy = mockPolicy()

    mockVerifiedFetch.mockImplementationOnce(async () => Response.json(mockedPolicy.asset))

    const asset = await complete(mockedPolicy, new AbortController().signal)

    expect(asset).toEqual(mockedPolicy.asset)

    expect(mockVerifiedFetch).toHaveBeenCalledTimes(1)
    const url = mockVerifiedFetch.mock.lastCall![0]
    const req = mockVerifiedFetch.mock.lastCall![1]!
    expect(req.body).toBeUndefined()
    expect(url).toEqual(mockedPolicy.asset_upload_url)
  })
})
