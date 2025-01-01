import {getTeam, getUser} from '../../test-utils/mock-data'
import {validateCampaign, type ValidateCampaignOptions, type ValidateCampaignParameters} from '../validate-campaign'

describe('validateCampaign', () => {
  const defaultParams: ValidateCampaignParameters = {
    name: 'User-controlled code injection',
    description:
      'Directly evaluating user input (for example, an HTTP request parameter) as code without first sanitizing the input allows an attacker arbitrary code execution.',
    dueDate: new Date('2024-05-12T00:00:00.000Z'),
    managers: [getUser()],
    teamManagers: [],
  }
  const defaultOptions: ValidateCampaignOptions = {
    descriptionDisplayMode: 'required',
    dueDateDisplayMode: 'required',
    allowDueDateInPast: true,
    maxManagers: 10,
  }

  const runValidateCampaign = (
    params: Partial<ValidateCampaignParameters> = {},
    options: Partial<ValidateCampaignOptions> = {},
  ) => {
    return validateCampaign(
      {
        ...defaultParams,
        ...params,
      },
      {
        ...defaultOptions,
        ...options,
      },
    )
  }

  test('is valid with valid parameters', () => {
    expect(runValidateCampaign()).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is invalid with missing parameters', () => {
    expect(
      validateCampaign(
        {
          name: '',
          description: '',
          dueDate: null,
          managers: [],
          teamManagers: [],
        },
        defaultOptions,
      ),
    ).toEqual({
      valid: false,
      invalidFields: ['name', 'description', 'dueDate', 'managers'],
    })
  })

  test('is invalid with missing name', () => {
    expect(
      runValidateCampaign({
        name: '',
      }),
    ).toEqual({
      valid: false,
      invalidFields: ['name'],
    })
  })

  test('is invalid with missing description', () => {
    expect(
      runValidateCampaign({
        description: '',
      }),
    ).toEqual({
      valid: false,
      invalidFields: ['description'],
    })
  })

  test('is valid with missing description when descriptionDisplayMode is optional', () => {
    expect(
      runValidateCampaign(
        {
          description: '',
        },
        {
          descriptionDisplayMode: 'optional',
        },
      ),
    ).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is valid with missing description when descriptionDisplayMode is hidden', () => {
    expect(
      runValidateCampaign(
        {
          description: '',
        },
        {
          descriptionDisplayMode: 'hidden',
        },
      ),
    ).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is invalid with missing due date', () => {
    expect(
      runValidateCampaign({
        dueDate: null,
      }),
    ).toEqual({
      valid: false,
      invalidFields: ['dueDate'],
    })
  })

  test('is valid with missing due date when dueDateDisplayMode is optional', () => {
    expect(
      runValidateCampaign(
        {
          dueDate: null,
        },
        {
          dueDateDisplayMode: 'optional',
        },
      ),
    ).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is valid with missing due date when dueDateDisplayMode is hidden', () => {
    expect(
      runValidateCampaign(
        {
          dueDate: null,
        },
        {
          dueDateDisplayMode: 'hidden',
        },
      ),
    ).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is valid with due date in past when allowDueDateInPast is true', () => {
    const pastDate = new Date()
    pastDate.setDate(pastDate.getDate() - 10)

    expect(
      runValidateCampaign(
        {
          dueDate: pastDate,
        },
        {
          allowDueDateInPast: true,
        },
      ),
    ).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is invalid with due date in past when allowDueDateInPast is false', () => {
    const pastDate = new Date()
    pastDate.setDate(pastDate.getDate() - 10)

    expect(
      runValidateCampaign(
        {
          dueDate: pastDate,
        },
        {
          allowDueDateInPast: false,
        },
      ),
    ).toEqual({
      valid: false,
      invalidFields: ['dueDate'],
    })
  })

  test('is valid with managers', () => {
    expect(
      runValidateCampaign({
        managers: [getUser()],
        teamManagers: [],
      }),
    ).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is valid with team managers', () => {
    expect(
      runValidateCampaign({
        managers: [],
        teamManagers: [getTeam()],
      }),
    ).toEqual({
      valid: true,
      invalidFields: [],
    })
  })

  test('is invalid with missing managers', () => {
    expect(
      runValidateCampaign({
        managers: [],
        teamManagers: [],
      }),
    ).toEqual({
      valid: false,
      invalidFields: ['managers'],
    })
  })

  test('is invalid with too many user managers', () => {
    expect(
      runValidateCampaign({
        managers: Array.from({length: 11}, () => getUser()),
        teamManagers: [],
      }),
    ).toEqual({
      valid: false,
      invalidFields: ['managers'],
    })
  })

  test('is invalid with too many team managers', () => {
    expect(
      runValidateCampaign({
        managers: [],
        teamManagers: Array.from({length: 11}, () => getTeam()),
      }),
    ).toEqual({
      valid: false,
      invalidFields: ['managers'],
    })
  })

  test('is invalid with too many combined managers', () => {
    expect(
      runValidateCampaign({
        managers: Array.from({length: 6}, () => getUser()),
        teamManagers: Array.from({length: 6}, () => getTeam()),
      }),
    ).toEqual({
      valid: false,
      invalidFields: ['managers'],
    })
  })
})
