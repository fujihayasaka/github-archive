import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {EducationSchoolsAutoComplete} from '../EducationSchoolsAutoComplete'

const applicationTypeSelectionClass = 'js-dev-pack-application-type-selection'
const autoCompleteContainerId = 'js-school-name-search-container'
const autoCompleteSearchClearButtonId = 'js-school-name-search-clear'
const containerId = 'education-schools-auto-complete-container'
const developerPackApplicationSubmitButtonId = 'developer-pack-application-submit-button'
const emailSelectionContainerId = 'js-email-selection-container'
const inputId = 'education-input'
const locationSharedInputId = 'location-shared'
const schoolChoice2faErrorElementId = 'school-choice-2fa-error'
const schoolChoiceAllowlistedDomainsBannerContainerId = 'school-choice-allowlisted-domains-banner-container'
const schoolChoiceAllowlistedDomainsBannerSchoolNameId = 'school-choice-allowlisted-domains-banner-school-name'
const schoolChoiceCaptionElementId = 'school-choice-caption'
const schoolChoiceDomainsListId = 'school-choice-domains-list'
const schoolChoiceFirstAllowlistedDomainId = 'school-choice-first-allowlisted-domain'
const schoolChoiceShowMoreDomainsButtonId = 'school-choice-show-more-domains-button'
const suggestedSchoolSelectButtonId = 'js-suggested-school-select-button'
const triggerElementClass = 'school-trigger'

const defaultValues = {
  emailDomains: '',
  isCameraRequired: false,
  isDistanceLimitOverridden: false,
  isNewSchool: true,
  isTwoFactorRequired: false,
  isUserTooFarFromSchool: false,
  selectedSchoolId: '',
}

const initialValues = {
  emailDomains: '[["test.edu",false,"MIXED_USE","ALLOWLISTED"]]',
  isCameraRequired: 'true',
  isDistanceLimitOverridden: 'true',
  isNewSchool: 'false',
  isTwoFactorRequired: 'true',
  isUserTooFarFromSchool: 'false',
  selectedSchoolId: '12345',
}

const setupDom = () => {
  document.body.innerHTML = `
    <div id="${containerId}">
      <input class="${applicationTypeSelectionClass}" type="radio" value="faculty" name="dev_pack_form[application_type]">
      <input class="${applicationTypeSelectionClass}" type="radio" value="student" name="dev_pack_form[application_type]">
      <div id="${autoCompleteContainerId}" data-testid="auto-complete-container">
        <input id="${inputId}" data-testid="input-element" type="text" />
        <div id="${emailSelectionContainerId}" data-testid="email-selection-container"></div>
        <button id="${suggestedSchoolSelectButtonId}" class="${triggerElementClass}" data-testid="suggested-school-select-button"></button>
      </div>
      <div class="${triggerElementClass}"
        data-selected-school-id=${initialValues.selectedSchoolId}
        data-two-factor-required=${initialValues.isTwoFactorRequired}
        data-override-distance-limit=${initialValues.isDistanceLimitOverridden}
        data-camera-required=${initialValues.isCameraRequired}
        data-email-domains=${initialValues.emailDomains}
        data-new-school=${initialValues.isNewSchool}
        data-user-too-far-from-school=${initialValues.isUserTooFarFromSchool}
        data-testid="trigger-element"
      >
        Test School
      </div>

      <input id="${locationSharedInputId}" data-testid="location-shared-input" type="hidden" value="true" />
      <button id="${autoCompleteSearchClearButtonId}" data-testid="clear-button"></button>
      <div id="${schoolChoice2faErrorElementId}" hidden="true" data-testid="school-choice-2fa-error"></div>
      <div id="${schoolChoiceCaptionElementId}" data-testid="school-choice-caption"></div>
      <button id="${developerPackApplicationSubmitButtonId}" data-testid="developer-pack-application-submit-button"></button>
      <div id="${schoolChoiceAllowlistedDomainsBannerContainerId}" data-testid="school-choice-allowlisted-domains-banner-container">
        <p id="${schoolChoiceAllowlistedDomainsBannerSchoolNameId}" data-testid="school-choice-allowlisted-domains-banner-school-name"></p>
        <ul>
          <li id="${schoolChoiceFirstAllowlistedDomainId}" data-testid="school-choice-first-allowlisted-domain"></li>
        </ul>
        <ul id="${schoolChoiceDomainsListId}" data-testid="school-choice-domains-list">
        </ul>
        <button id="${schoolChoiceShowMoreDomainsButtonId}" data-testid="school-choice-show-more-domains-button"></button>
      </div>
    </div>
  `
}

const renderComponent = () => {
  return render(
    <EducationSchoolsAutoComplete
      {...{
        applicationTypeSelectionClass,
        autoCompleteContainerId,
        autoCompleteSearchClearButtonId,
        containerId,
        developerPackApplicationSubmitButtonId,
        emailSelectionContainerId,
        inputId,
        locationSharedInputId,
        schoolChoice2faErrorElementId,
        schoolChoiceAllowlistedDomainsBannerContainerId,
        schoolChoiceAllowlistedDomainsBannerSchoolNameId,
        schoolChoiceCaptionElementId,
        schoolChoiceDomainsListId,
        schoolChoiceFirstAllowlistedDomainId,
        schoolChoiceShowMoreDomainsButtonId,
        suggestedSchoolSelectButtonId,
        triggerElementClass,
      }}
    />,
  )
}

const convertKeyToTestId = (key: string) => {
  const camelCasedTestId = key.replace(/^is/, '')
  return camelCasedTestId.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase()
}

describe('EducationSchoolsAutoComplete', () => {
  beforeEach(() => setupDom())

  test('updates hidden inputs for the selected school when a school is selected from the autocomplete options', async () => {
    const {user} = renderComponent()
    const triggerElement = screen.getByTestId('trigger-element')
    await user.click(triggerElement)

    for (const [key, value] of Object.entries(initialValues)) {
      await waitFor(() => {
        expect(screen.getByTestId(convertKeyToTestId(key))).toHaveValue(String(value))
      })
    }
  })

  test('resets the hidden fields to default values when the user types in the input box', async () => {
    const {user} = renderComponent()
    const triggerElement = screen.getByTestId('trigger-element')
    await user.click(triggerElement)

    for (const [key, value] of Object.entries(initialValues)) {
      await waitFor(() => {
        expect(screen.getByTestId(convertKeyToTestId(key))).toHaveValue(String(value))
      })
    }

    const inputElement = screen.getByTestId('input-element')
    await user.type(inputElement, 'a')

    await waitFor(() => {
      for (const [key, value] of Object.entries(defaultValues)) {
        expect(screen.getByTestId(convertKeyToTestId(key))).toHaveValue(String(value))
      }
    })
  })

  test('shows the 2FA error message when the user is required to use 2FA', async () => {
    const {user} = renderComponent()
    const triggerElement = screen.getByTestId('trigger-element')

    await user.click(triggerElement)

    const twoFactorRequired = screen.getByTestId('two-factor-required')
    await waitFor(() => {
      expect(twoFactorRequired).toHaveValue('true')
    })

    const schoolChoice2faError = screen.getByTestId('school-choice-2fa-error')
    await waitFor(() => {
      expect(schoolChoice2faError).toBeVisible()
    })
  })

  test('clears the form and resets everything when the clear button is pressed', async () => {
    const {user} = renderComponent()
    const triggerElement = screen.getByTestId('trigger-element')

    await user.click(triggerElement)
    await waitFor(() => {
      for (const [key, value] of Object.entries(initialValues)) {
        expect(screen.getByTestId(convertKeyToTestId(key))).toHaveValue(String(value))
      }
    })

    const clearButton = screen.getByTestId('clear-button')

    await user.click(clearButton)
    await waitFor(() => {
      for (const [key, value] of Object.entries(defaultValues)) {
        expect(screen.getByTestId(convertKeyToTestId(key))).toHaveValue(String(value))
      }
    })

    const schoolChoice2faError = screen.getByTestId('school-choice-2fa-error')
    await waitFor(() => {
      expect(schoolChoice2faError).not.toBeVisible()
    })
  })

  test('does not show the "Show more" button when there are no additional domains', async () => {
    const {user} = renderComponent()
    const triggerElement = screen.getByTestId('trigger-element')

    await user.click(triggerElement)
    const schoolChoiceShowMoreDomainsButton = screen.getByTestId('school-choice-show-more-domains-button')
    await waitFor(() => {
      expect(schoolChoiceShowMoreDomainsButton).not.toBeVisible()
    })
  })
})
