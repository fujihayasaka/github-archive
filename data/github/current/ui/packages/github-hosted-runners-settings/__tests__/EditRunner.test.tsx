import {act, fireEvent, screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {getRunnerEditForm, getEditRunnerRoutePayload, getMachineSpec} from '../test-utils/mock-data'
import {EditRunner, type EditRunnerPayload} from '../routes/EditRunner'
import {runnerDetailsPath, updateRunnerPath} from '../helpers/paths'
import {ImageSource, type Image, type ImageVersion} from '../types/image'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

beforeEach(() => {
  setupVerifiedFetch()
})

function setupVerifiedFetch(response?: {}) {
  mockVerifiedFetchJSON.mockClear()
  mockVerifiedFetchJSON.mockImplementation((url: string) => {
    if (url.includes('public_ip_info')) {
      return {
        ok: true,
        statusText: 'OK',
        json: async () => {
          return {
            usedIpCount: 0,
            totalIpCount: 10,
          }
        },
      }
    }
    return response
  })
}

async function renderComponentUnderTest(routePayload: EditRunnerPayload) {
  render(
    // Put FF's that you are testing in here
    <FeatureFlagProvider features={{}}>
      <EditRunner />
    </FeatureFlagProvider>,
    {routePayload},
  )

  // Resolve the public IP checkbox fetch
  await act(() => expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(routePayload.publicIpInfoPath))
}

describe('EditRunner rendering', () => {
  test('Main form elements are rendered', async () => {
    const routePayload = getEditRunnerRoutePayload()
    await renderComponentUnderTest(routePayload)

    expect(screen.getByTestId('subhead-runner-list-path')).toHaveAttribute('href', routePayload.runnerListPath)
    expect(screen.getByTestId('runner-name-input-section')).toBeVisible()
    expect(screen.getByTestId('runner-public-ip-checkbox')).toBeVisible()
    expect(screen.getByTestId('edit-runner-save-button')).toBeVisible()
    expect(screen.getByTestId('edit-runner-cancel-button')).toBeVisible()
    expect(screen.getByTestId('runner-group-section')).toBeVisible()
  })

  test('"Runner specifications" section is visible when runner has a custom image', async () => {
    const routePayload = getEditRunnerRoutePayload()
    await renderComponentUnderTest(routePayload)

    expect(screen.getByTestId('edit-runner-specifications-section')).toBeVisible()
  })
})

describe('EditRunner form submission', () => {
  test('Basic form (changing runner name) submits and redirects', async () => {
    setupVerifiedFetch({
      ok: true,
      status: 200,
      json: async () => {
        return {success: true, errors: []}
      },
    })

    const routePayload = getEditRunnerRoutePayload({
      images: {
        github: [{id: '1', source: ImageSource.Curated} as Image],
      },
      runnerImage: {id: '1', source: ImageSource.Curated, version: '1'},
    })
    const runnerId = routePayload.runnerId
    const editedRunnerName = 'EditedRunnerName'

    await renderComponentUnderTest(routePayload)

    // update runner name
    const runnerNameInput = screen.getByTestId('runner-name-input') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(runnerNameInput, {target: {value: editedRunnerName}})

    // submit form
    const submitBtn = screen.getByTestId('edit-runner-save-button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(submitBtn)

    // verify expected form submission
    const expectedRunnerEditForm = getRunnerEditForm({
      name: editedRunnerName,
      machineSpecId: routePayload.runnerMachineSpecId,
      imageId: routePayload.runnerImage.id as string,
    })
    await act(() =>
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
        updateRunnerPath({isEnterprise: false, entityLogin: routePayload.entityLogin, runnerId}),
        {
          method: 'PATCH',
          body: expectedRunnerEditForm,
        },
      ),
    )

    // verify navigation to org runner details page
    expect(navigateFn).toHaveBeenCalledWith(
      runnerDetailsPath({isEnterprise: false, entityLogin: routePayload.entityLogin, runnerId}),
    )
  })

  test('form cannot be submitted if validation failed', async () => {
    const updateRunnerFn = jest.fn()
    jest.mock('../services/runner', () => {
      return {
        ...jest.requireActual('../services/runner'),
        createRunner: updateRunnerFn,
      }
    })
    const routePayload = getEditRunnerRoutePayload()
    await renderComponentUnderTest(routePayload)

    // update runner name to blank
    const runnerNameInput = screen.getByTestId('runner-name-input')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(runnerNameInput, {target: {value: ''}})
    // eslint-disable-next-line github/no-blur
    fireEvent.blur(runnerNameInput)

    const submitBtn = screen.getByTestId('edit-runner-save-button')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(submitBtn)

    await waitFor(() => expect(runnerNameInput).toHaveAttribute('aria-invalid', 'true'))
    await act(async () => expect(updateRunnerFn).not.toHaveBeenCalled())
  })

  test('cancel button navigates to runner details page', async () => {
    const routePayload = getEditRunnerRoutePayload()
    await renderComponentUnderTest(routePayload)

    const cancelBtn = screen.getByTestId('edit-runner-cancel-button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(cancelBtn)

    expect(navigateFn).toHaveBeenCalledWith(
      runnerDetailsPath({isEnterprise: false, entityLogin: routePayload.entityLogin, runnerId: routePayload.runnerId}),
    )
  })

  test('edit machine spec shows machine specs that satisfy storage requirments for curated', async () => {
    const routePayload = getEditRunnerRoutePayload({
      images: {
        github: [{id: '1', latestVersionSizeGb: 50} as Image],
      },
      runnerImage: {id: '1', source: ImageSource.Curated, version: '1'},
      machineSpecs: [
        getMachineSpec({id: 'large-spec', storageGb: 100}),
        getMachineSpec({id: 'sufficient-spec', storageGb: 50}),
        getMachineSpec({id: 'small-spec', storageGb: 25}),
      ],
      runnerMachineSpecId: 'large-spec', // edit button won't show without this
    })

    await renderComponentUnderTest(routePayload)

    // open machine spec edit component
    const editButton = screen.getByTestId('field-progression-field-edit-button-0') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(editButton)

    expect(screen.getByTestId('runner-machine-spec-select')).toBeInTheDocument()
    expect(screen.queryByTestId('runner-machine-spec-radio-small-spec')).not.toBeInTheDocument()
    expect(screen.getByTestId('runner-machine-spec-radio-sufficient-spec')).toBeInTheDocument()
    expect(screen.getByTestId('runner-machine-spec-radio-large-spec')).toBeInTheDocument()
  })

  test('edit machine spec shows machine specs that satisfy storage requirments for custom', async () => {
    const routePayload = getEditRunnerRoutePayload({
      imageVersions: [{version: '1', size: 50} as ImageVersion, {version: '2', size: 100} as ImageVersion],
      runnerImage: {id: '1', source: ImageSource.Custom, version: '1'},
      machineSpecs: [
        getMachineSpec({id: 'large-spec', storageGb: 100}),
        getMachineSpec({id: 'sufficient-spec', storageGb: 50}),
        getMachineSpec({id: 'small-spec', storageGb: 25}),
      ],
      runnerMachineSpecId: 'large-spec', // edit button won't show without this
    })

    await renderComponentUnderTest(routePayload)

    // open machine spec edit component
    const editButton = screen.getByTestId('field-progression-field-edit-button-0') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(editButton)

    expect(screen.getByTestId('runner-machine-spec-select')).toBeInTheDocument()
    expect(screen.queryByTestId('runner-machine-spec-radio-small-spec')).not.toBeInTheDocument()
    expect(screen.getByTestId('runner-machine-spec-radio-sufficient-spec')).toBeInTheDocument()
    expect(screen.getByTestId('runner-machine-spec-radio-large-spec')).toBeInTheDocument()
  })

  test('image selector is visible when image source is curated', async () => {
    const routePayload = getEditRunnerRoutePayload({
      images: {
        github: [{id: '1', source: ImageSource.Curated} as Image],
      },
      runnerImage: {id: '1', source: ImageSource.Curated, version: '1'},
    })

    await renderComponentUnderTest(routePayload)

    // open image selector component
    const editButton = screen.getByTestId('field-progression-field-edit-button-0') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(editButton)

    expect(screen.getByTestId('image-selector-tab-content')).toBeInTheDocument()
  })

  test('image selector is not visible when FF is on and image source is non-curated', async () => {
    const routePayload = getEditRunnerRoutePayload({
      images: {
        github: [{id: '1', source: ImageSource.Custom} as Image],
      },
      runnerImage: {id: '1', source: ImageSource.Custom, version: '1'},
    })

    await renderComponentUnderTest(routePayload)

    expect(screen.queryByTestId('image-selector-tab-content')).not.toBeInTheDocument()
  })
})
