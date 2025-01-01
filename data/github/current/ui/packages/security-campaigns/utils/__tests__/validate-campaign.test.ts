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
    contactLink: null,
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
      fieldValidationErrors: {},
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
          contactLink: null,
        },
        defaultOptions,
      ),
    ).toEqual({
      valid: false,
      fieldValidationErrors: {
        description: 'Description must be between 1 and 255 characters long',
        dueDate: 'Due date is required',
        managers: 'You must have at least one manager and at most 10 managers',
        name: 'Name must be between 1 and 50 characters long',
      },
    })
  })

  test('is invalid with missing name', () => {
    expect(
      runValidateCampaign({
        name: '',
      }),
    ).toEqual({
      valid: false,
      fieldValidationErrors: {
        name: 'Name must be between 1 and 50 characters long',
      },
    })
  })

  test('is invalid with missing description', () => {
    expect(
      runValidateCampaign({
        description: '',
      }),
    ).toEqual({
      valid: false,
      fieldValidationErrors: {
        description: 'Description must be between 1 and 255 characters long',
      },
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
      fieldValidationErrors: {},
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
      fieldValidationErrors: {},
    })
  })

  test('is invalid with missing due date', () => {
    expect(
      runValidateCampaign({
        dueDate: null,
      }),
    ).toEqual({
      valid: false,
      fieldValidationErrors: {
        dueDate: 'Due date is required',
      },
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
      fieldValidationErrors: {},
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
      fieldValidationErrors: {},
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
      fieldValidationErrors: {},
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
      fieldValidationErrors: {
        dueDate: 'Due date must be in the future',
      },
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
      fieldValidationErrors: {},
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
      fieldValidationErrors: {},
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
      fieldValidationErrors: {
        managers: 'You must have at least one manager and at most 10 managers',
      },
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
      fieldValidationErrors: {
        managers: 'You must have at least one manager and at most 10 managers',
      },
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
      fieldValidationErrors: {
        managers: 'You must have at least one manager and at most 10 managers',
      },
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
      fieldValidationErrors: {
        managers: 'You must have at least one manager and at most 10 managers',
      },
    })
  })

  test('is valid with https contact link', () => {
    expect(
      runValidateCampaign({
        contactLink: 'https://example.com',
      }),
    ).toEqual({
      valid: true,
      fieldValidationErrors: {},
    })
  })

  test('is valid with http contact link', () => {
    expect(
      runValidateCampaign({
        contactLink: 'http://example.com',
      }),
    ).toEqual({
      valid: true,
      fieldValidationErrors: {},
    })
  })

  test('is valid with mailto contact link', () => {
    expect(
      runValidateCampaign({
        contactLink: 'mailto:@test.com',
      }),
    ).toEqual({
      valid: true,
      fieldValidationErrors: {},
    })
  })

  test('is invalid with invalid contact link (script)', () => {
    expect(
      runValidateCampaign({
        contactLink: "javascript:alert('xss')",
      }),
    ).toEqual({
      valid: false,
      fieldValidationErrors: {
        contactLink: 'Contact link must use http, https or mailto scheme',
      },
    })
  })

  test('is invalid with invalid contact link (text)', () => {
    expect(
      runValidateCampaign({
        contactLink: 'invalid link',
      }),
    ).toEqual({
      valid: false,
      fieldValidationErrors: {
        contactLink: 'Contact link must use http, https or mailto scheme',
      },
    })
  })
})
