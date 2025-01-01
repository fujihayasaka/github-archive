import {useCallback, useEffect, useState} from 'react'
import {HiddenInputs} from './HiddenInputs'
import {toggleVisibility, toggleContainerVisibility} from './utils'

import type {EmailDomainData, EducationSchoolsAutoCompleteProps} from './types'

const defaultValues = {
  emailDomains: '',
  isCameraRequired: false,
  isDistanceLimitOverridden: false,
  isNewSchool: true,
  isTwoFactorRequired: false,
  isUserTooFarFromSchool: false,
  selectedSchoolId: '',
}

export function EducationSchoolsAutoComplete(props: EducationSchoolsAutoCompleteProps) {
  const [values, setValues] = useState(defaultValues)
  const [applicationType, setApplicationType] = useState<'STUDENT' | 'FACULTY' | 'MIXED_USE'>('MIXED_USE')
  const [suggestedSchoolHasBeenSelected, setSuggestedSchoolHasBeenSelected] = useState(false)
  const [locationHasBeenShared, setLocationHasBeenShared] = useState(false)
  const [submitButtonEnabled, setSubmitButtonEnabled] = useState(false)
  const [customSchoolInput, setCustomSchoolInput] = useState('')

  const applicationTypeSelectionClickHandler = useCallback(
    async (event: Event) => {
      if (!suggestedSchoolHasBeenSelected) {
        const clearButton = document.getElementById(props.autoCompleteSearchClearButtonId) as HTMLButtonElement
        if (clearButton) clearButton.click()
      }

      const schoolChoiceShowMoreDomainsButton = document.getElementById(
        props.schoolChoiceShowMoreDomainsButtonId,
      ) as HTMLButtonElement
      if (schoolChoiceShowMoreDomainsButton && schoolChoiceShowMoreDomainsButton.textContent === 'Show less') {
        schoolChoiceShowMoreDomainsButton.click()
      }

      if (!suggestedSchoolHasBeenSelected) {
        const suggestedSchoolSelectButton = document.getElementById(props.suggestedSchoolSelectButtonId)
        const schoolChoiceCaptionElement = document.getElementById(
          props.schoolChoiceCaptionElementId,
        ) as HTMLParagraphElement
        if (
          schoolChoiceCaptionElement &&
          !schoolChoiceCaptionElement.hidden &&
          suggestedSchoolSelectButton &&
          suggestedSchoolSelectButton.textContent === 'Unselect this school'
        ) {
          schoolChoiceCaptionElement.hidden = true
        } else if (schoolChoiceCaptionElement) {
          schoolChoiceCaptionElement.hidden = false
        }
      }

      const target = event.currentTarget as HTMLInputElement
      const targetApplicationType = target.value

      if (targetApplicationType === 'student') {
        setApplicationType('STUDENT')
      } else if (targetApplicationType === 'faculty') {
        setApplicationType('FACULTY')
      } else {
        setApplicationType('MIXED_USE')
      }
    },
    [
      props.autoCompleteSearchClearButtonId,
      props.schoolChoiceShowMoreDomainsButtonId,
      props.schoolChoiceCaptionElementId,
      props.suggestedSchoolSelectButtonId,
      suggestedSchoolHasBeenSelected,
    ],
  )

  const show2faError = useCallback(
    async () => toggleVisibility(`#${props.schoolChoice2faErrorElementId}`, true),
    [props.schoolChoice2faErrorElementId],
  )

  const hide2faError = useCallback(
    async () => toggleVisibility(`#${props.schoolChoice2faErrorElementId}`, false),
    [props.schoolChoice2faErrorElementId],
  )

  const showCaption = useCallback(
    async () => toggleVisibility(`#${props.schoolChoiceCaptionElementId}`, true),
    [props.schoolChoiceCaptionElementId],
  )

  const hideCaption = useCallback(
    async () => toggleVisibility(`#${props.schoolChoiceCaptionElementId}`, false),
    [props.schoolChoiceCaptionElementId],
  )

  const showEmailSelectionContainer = useCallback(
    async () => toggleContainerVisibility(`#${props.emailSelectionContainerId}`, '.FormControl', true),
    [props.emailSelectionContainerId],
  )

  const hideAllowlistedDomainsError = useCallback(
    async () => toggleVisibility(`#${props.schoolChoiceAllowlistedDomainsBannerContainerId}`, false),
    [props.schoolChoiceAllowlistedDomainsBannerContainerId],
  )

  const showAllowlistedDomainsError = useCallback(
    async () => toggleVisibility(`#${props.schoolChoiceAllowlistedDomainsBannerContainerId}`, true),
    [props.schoolChoiceAllowlistedDomainsBannerContainerId],
  )

  const hideEmailSelectionContainer = useCallback(
    async () => toggleContainerVisibility(`#${props.emailSelectionContainerId}`, '.FormControl', false),
    [props.emailSelectionContainerId],
  )

  const emailDomains = useCallback(
    async (target: HTMLElement) => {
      const rawEmailData = JSON.parse(target.getAttribute('data-email-domains') || '[]') as Array<
        [string, boolean, string, string]
      >
      const domains: EmailDomainData[] = rawEmailData.map(([domain, ignoresDistanceLimit, domainKind, state]) => ({
        domain,
        ignoresDistanceLimit,
        domainKind,
        state,
      }))

      return domains.filter(domain => domain.domainKind === applicationType || domain.domainKind === 'MIXED_USE')
    },
    [applicationType],
  )

  const setValuesFromTarget = useCallback(async (target: HTMLElement, isTwoFactorRequired: boolean) => {
    setValues({
      emailDomains: target.getAttribute('data-email-domains') || '[]',
      isCameraRequired: target.getAttribute('data-camera-required') === 'true',
      isDistanceLimitOverridden: target.getAttribute('data-override-distance-limit') === 'true',
      isNewSchool: false,
      isTwoFactorRequired,
      isUserTooFarFromSchool: target.getAttribute('data-user-too-far-from-school') === 'true',
      selectedSchoolId: target.getAttribute('data-selected-school-id') || '',
    })
  }, [])

  const setSchoolAttributesOnBanner = useCallback(
    async (target: HTMLElement) => {
      const schoolChoiceAllowlistedDomainsBannerSchoolName = document.getElementById(
        props.schoolChoiceAllowlistedDomainsBannerSchoolNameId,
      ) as HTMLSpanElement
      const schoolName = target.getAttribute('data-school-name')
      const allowlistedDomain = document.getElementById(props.schoolChoiceFirstAllowlistedDomainId) as HTMLLIElement
      const domains = await emailDomains(target)
      const allowlistedDomainName = domains.find(domain => domain.state === 'ALLOWLISTED')?.domain
      const otherDomains = domains.filter(domain => domain.domain !== allowlistedDomainName)

      if (otherDomains.length === 0) toggleVisibility(`#${props.schoolChoiceShowMoreDomainsButtonId}`, false)

      if (schoolChoiceAllowlistedDomainsBannerSchoolName && schoolName && allowlistedDomain && allowlistedDomainName) {
        schoolChoiceAllowlistedDomainsBannerSchoolName.textContent = schoolName
        allowlistedDomain.textContent = allowlistedDomainName

        const domainList = document.getElementById(props.schoolChoiceDomainsListId) as HTMLUListElement
        if (domainList && otherDomains.length > 0) {
          for (const domain of otherDomains) {
            const domainListItem = document.createElement('li')
            domainListItem.textContent = domain.domain
            domainList.appendChild(domainListItem)
          }
        }
      }
    },
    [
      emailDomains,
      props.schoolChoiceAllowlistedDomainsBannerSchoolNameId,
      props.schoolChoiceDomainsListId,
      props.schoolChoiceFirstAllowlistedDomainId,
      props.schoolChoiceShowMoreDomainsButtonId,
    ],
  )

  const handleAllowlistDomainBlocks = useCallback(
    async (target: HTMLElement) => {
      const userHasEmailForSchool = target.getAttribute('data-user-has-email-for-school') === 'true'
      const domains = await emailDomains(target)
      const schoolHasAllowlistedDomain = domains.some((domain: EmailDomainData) => domain.state === 'ALLOWLISTED')

      if (schoolHasAllowlistedDomain) {
        if (userHasEmailForSchool) {
          hideAllowlistedDomainsError()
          return false
        } else {
          setSchoolAttributesOnBanner(target)
          showAllowlistedDomainsError()
          return true
        }
      } else {
        hideAllowlistedDomainsError()
        return false
      }
    },
    [emailDomains, hideAllowlistedDomainsError, setSchoolAttributesOnBanner, showAllowlistedDomainsError],
  )

  const clickHandler = useCallback(
    async (event: Event) => {
      const target = event.currentTarget as HTMLElement
      const isTwoFactorRequired = target.getAttribute('data-two-factor-required') === 'true'

      setValuesFromTarget(target, isTwoFactorRequired)
      const isAllowlistDomainBlocked = await handleAllowlistDomainBlocks(target)

      if (isTwoFactorRequired) {
        show2faError()
        hideCaption()
      } else {
        hide2faError()
        showCaption()
      }

      if (isTwoFactorRequired || isAllowlistDomainBlocked) {
        setSubmitButtonEnabled(false)
      } else {
        setSubmitButtonEnabled(true)
      }
    },
    [
      setSubmitButtonEnabled,
      handleAllowlistDomainBlocks,
      hide2faError,
      hideCaption,
      setValuesFromTarget,
      show2faError,
      showCaption,
    ],
  )

  const clearOutEmailDomainsList = useCallback(async () => {
    const schoolChoiceDomainsList = document.getElementById(props.schoolChoiceDomainsListId) as HTMLUListElement
    if (schoolChoiceDomainsList) {
      schoolChoiceDomainsList.textContent = ''
    }
  }, [props.schoolChoiceDomainsListId])

  const resetValues = useCallback(async () => {
    hide2faError()
    hideAllowlistedDomainsError()
    showCaption()
    setSubmitButtonEnabled(false)
    clearOutEmailDomainsList()
    setValues(defaultValues)
    setCustomSchoolInput('')
  }, [clearOutEmailDomainsList, setSubmitButtonEnabled, hide2faError, hideAllowlistedDomainsError, showCaption])

  const showMoreDomainsClickHandler = useCallback(async () => {
    const schoolChoiceShowMoreDomainsButton = document.getElementById(
      props.schoolChoiceShowMoreDomainsButtonId,
    ) as HTMLButtonElement
    const domainList = document.getElementById(props.schoolChoiceDomainsListId) as HTMLUListElement

    if (domainList && schoolChoiceShowMoreDomainsButton) {
      const buttonLabel = schoolChoiceShowMoreDomainsButton.querySelector('.Button-label')
      if (!buttonLabel) return

      if (buttonLabel.textContent === 'Show more') {
        buttonLabel.textContent = 'Show less'
        domainList.hidden = false
      } else {
        buttonLabel.textContent = 'Show more'
        domainList.hidden = true
      }
    }
  }, [props.schoolChoiceDomainsListId, props.schoolChoiceShowMoreDomainsButtonId])

  const suggestedSchoolClickHandler = useCallback(
    async (event: Event) => {
      const target = event.currentTarget as HTMLElement

      const autoCompleteContainer = document.getElementById(props.autoCompleteContainerId) as HTMLInputElement
      if (!autoCompleteContainer) return

      const currentSelectionStatus = target.getAttribute('data-selected') || 'false'
      target.setAttribute('data-selected', currentSelectionStatus === 'true' ? 'false' : 'true')
      const userIsUnselecting = currentSelectionStatus === 'true'

      const isTwoFactorRequired = target.getAttribute('data-two-factor-required') === 'true'

      if (userIsUnselecting) {
        setSubmitButtonEnabled(false)
        setSuggestedSchoolHasBeenSelected(false)
        target.textContent = 'Select this school'
        autoCompleteContainer.hidden = false
        autoCompleteContainer.value = ''
        setCustomSchoolInput('')
        showEmailSelectionContainer()
        resetValues()
      } else {
        setSuggestedSchoolHasBeenSelected(true)
        target.textContent = 'Unselect this school'
        autoCompleteContainer.hidden = true
        autoCompleteContainer.value = target.getAttribute('data-school-name') || ''
        hideEmailSelectionContainer()
        hideAllowlistedDomainsError()

        setValuesFromTarget(target, isTwoFactorRequired)

        hideCaption()

        if (isTwoFactorRequired) {
          show2faError()
        } else {
          setSubmitButtonEnabled(true)
          hide2faError()
        }
      }
    },
    [
      setSubmitButtonEnabled,
      hide2faError,
      hideAllowlistedDomainsError,
      hideCaption,
      hideEmailSelectionContainer,
      props.autoCompleteContainerId,
      resetValues,
      setValuesFromTarget,
      show2faError,
      showEmailSelectionContainer,
    ],
  )

  const handleCustomSchoolInputChange = useCallback(
    (event: Event) => {
      const target = event.target as HTMLInputElement
      const value = target.value || ''
      setCustomSchoolInput(value)

      if (value.length > 0) {
        setValues(prev => ({
          ...prev,
          isNewSchool: true,
          selectedSchoolId: '',
        }))
      }
    },
    [setCustomSchoolInput, setValues],
  )

  const addClickHandlers = useCallback(
    async (container: HTMLElement) => {
      const triggerElements = container.querySelectorAll(`.${props.triggerElementClass}`)
      for (const el of triggerElements) {
        el.addEventListener('click', clickHandler)
      }

      const applicationTypeSelections = document.querySelectorAll(`.${props.applicationTypeSelectionClass}`)
      for (const el of applicationTypeSelections) {
        el.addEventListener('click', applicationTypeSelectionClickHandler)
      }

      const suggestedSchoolSelectButton = document.getElementById(props.suggestedSchoolSelectButtonId)
      if (suggestedSchoolSelectButton) {
        suggestedSchoolSelectButton.addEventListener('click', suggestedSchoolClickHandler)
      }

      const schoolChoiceShowMoreDomainsButton = document.getElementById(
        props.schoolChoiceShowMoreDomainsButtonId,
      ) as HTMLButtonElement
      if (schoolChoiceShowMoreDomainsButton) {
        schoolChoiceShowMoreDomainsButton.addEventListener('click', showMoreDomainsClickHandler)
      }

      const clearButton = document.getElementById(props.autoCompleteSearchClearButtonId)
      if (clearButton) clearButton.addEventListener('click', resetValues)

      const autoCompleteInput = document.getElementById(props.autoCompleteContainerId) as HTMLInputElement
      if (autoCompleteInput) {
        autoCompleteInput.addEventListener('input', handleCustomSchoolInputChange)
      }
    },
    [
      applicationTypeSelectionClickHandler,
      clickHandler,
      handleCustomSchoolInputChange,
      props.applicationTypeSelectionClass,
      props.autoCompleteContainerId,
      props.autoCompleteSearchClearButtonId,
      props.schoolChoiceShowMoreDomainsButtonId,
      props.suggestedSchoolSelectButtonId,
      props.triggerElementClass,
      resetValues,
      showMoreDomainsClickHandler,
      suggestedSchoolClickHandler,
    ],
  )

  const addInputListener = useCallback(async () => {
    const inputField = document.getElementById(props.inputId)
    if (inputField) inputField.addEventListener('input', resetValues)
  }, [props.inputId, resetValues])

  const removeInputListener = useCallback(async () => {
    const inputField = document.getElementById(props.inputId)
    if (inputField) inputField.removeEventListener('input', resetValues)
  }, [props.inputId, resetValues])

  const removeClickHandlers = useCallback(
    async (container: HTMLElement) => {
      const triggerElements = container.querySelectorAll(`.${props.triggerElementClass}`)
      for (const el of triggerElements) {
        el.removeEventListener('click', clickHandler)
      }

      const applicationTypeSelections = document.querySelectorAll(`.${props.applicationTypeSelectionClass}`)
      for (const el of applicationTypeSelections) {
        el.removeEventListener('click', applicationTypeSelectionClickHandler)
      }

      const suggestedSchoolSelectButton = document.getElementById(props.suggestedSchoolSelectButtonId)
      if (suggestedSchoolSelectButton) {
        suggestedSchoolSelectButton.removeEventListener('click', suggestedSchoolClickHandler)
      }

      const schoolChoiceShowMoreDomainsButton = document.getElementById(
        props.schoolChoiceShowMoreDomainsButtonId,
      ) as HTMLButtonElement
      if (schoolChoiceShowMoreDomainsButton) {
        schoolChoiceShowMoreDomainsButton.removeEventListener('click', showMoreDomainsClickHandler)
      }

      const clearButton = document.getElementById(props.autoCompleteSearchClearButtonId)
      if (clearButton) clearButton.removeEventListener('click', resetValues)

      const autoCompleteInput = document.getElementById(props.autoCompleteContainerId) as HTMLInputElement
      if (autoCompleteInput) {
        autoCompleteInput.removeEventListener('input', handleCustomSchoolInputChange)
      }
    },
    [
      applicationTypeSelectionClickHandler,
      suggestedSchoolClickHandler,
      showMoreDomainsClickHandler,
      clickHandler,
      handleCustomSchoolInputChange,
      props.applicationTypeSelectionClass,
      props.autoCompleteContainerId,
      props.autoCompleteSearchClearButtonId,
      props.schoolChoiceShowMoreDomainsButtonId,
      props.suggestedSchoolSelectButtonId,
      props.triggerElementClass,
      resetValues,
    ],
  )

  useEffect(() => {
    const container = document.getElementById(props.containerId) as HTMLElement
    if (!container) return

    addClickHandlers(container)
    addInputListener()

    const observer = new MutationObserver(mutationsList => {
      for (const mutation of mutationsList) {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          addClickHandlers(container)
        }
      }
    })

    observer.observe(container, {childList: true, subtree: true})

    return () => {
      observer.disconnect()
      removeClickHandlers(container)
      removeInputListener()
    }
  }, [addClickHandlers, addInputListener, props.containerId, removeClickHandlers, removeInputListener])

  useEffect(() => {
    const locationSharedInputElement = document.getElementById(props.locationSharedInputId) as HTMLInputElement | null
    if (!locationSharedInputElement) return

    const handleChange = () => setLocationHasBeenShared(locationSharedInputElement.value === 'true')
    handleChange()

    const observer = new MutationObserver(() => handleChange())
    observer.observe(locationSharedInputElement, {attributes: true})

    return () => observer.disconnect()
  }, [props.locationSharedInputId, setLocationHasBeenShared])

  useEffect(() => {
    if (!suggestedSchoolHasBeenSelected && customSchoolInput.length > 3) {
      setValues(prev => ({
        ...prev,
        isNewSchool: true,
      }))
      hideAllowlistedDomainsError()
      hide2faError()
      setSubmitButtonEnabled(true)
    } else if (!suggestedSchoolHasBeenSelected && customSchoolInput.length > 0 && customSchoolInput.length <= 3) {
      setSubmitButtonEnabled(false)
    }
  }, [customSchoolInput, suggestedSchoolHasBeenSelected, hide2faError, hideAllowlistedDomainsError])

  useEffect(() => {
    const submitButton = document.getElementById(props.developerPackApplicationSubmitButtonId) as HTMLButtonElement
    if (!submitButton) return

    if (submitButtonEnabled && locationHasBeenShared) {
      submitButton.disabled = false
    } else {
      submitButton.disabled = true
    }
  }, [props.developerPackApplicationSubmitButtonId, submitButtonEnabled, locationHasBeenShared])

  return (
    <HiddenInputs
      emailDomains={values.emailDomains}
      isCameraRequired={String(values.isCameraRequired)}
      isDistanceLimitOverridden={String(values.isDistanceLimitOverridden)}
      isNewSchool={String(values.isNewSchool)}
      isTwoFactorRequired={String(values.isTwoFactorRequired)}
      isUserTooFarFromSchool={String(values.isUserTooFarFromSchool)}
      selectedSchoolId={values.selectedSchoolId}
    />
  )
}
