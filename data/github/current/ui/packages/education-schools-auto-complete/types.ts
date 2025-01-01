export interface EmailDomainData {
  domain: string
  ignoresDistanceLimit: boolean
  domainKind: string
  state: string
}

export interface EducationSchoolsAutoCompleteProps {
  applicationTypeSelectionClass: string
  autoCompleteContainerId: string
  autoCompleteSearchClearButtonId: string
  containerId: string
  developerPackApplicationSubmitButtonId: string
  emailSelectionContainerId: string
  inputId: string
  locationSharedInputId: string
  schoolChoice2faErrorElementId: string
  schoolChoiceAllowlistedDomainsBannerContainerId: string
  schoolChoiceAllowlistedDomainsBannerSchoolNameId: string
  schoolChoiceCaptionElementId: string
  schoolChoiceDomainsListId: string
  schoolChoiceFirstAllowlistedDomainId: string
  schoolChoiceShowMoreDomainsButtonId: string
  suggestedSchoolSelectButtonId: string
  triggerElementClass: string
}
