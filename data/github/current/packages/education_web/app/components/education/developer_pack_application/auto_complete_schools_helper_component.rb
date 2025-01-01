# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class AutoCompleteSchoolsHelperComponent < ApplicationComponent
      PARTIAL_NAME = T.let("education-schools-auto-complete".freeze, String)

      sig { returns(String) }
      def call
        content_tag(
          :div,
          render_react_partial(
            name: PARTIAL_NAME,
            props: {
              applicationTypeSelectionClass: "js-dev-pack-application-type-selection",
              autoCompleteContainerId: "js-school-name-search-container",
              autoCompleteSearchClearButtonId: "js-school-name-search-clear",
              containerId: "js-school-name-list",
              developerPackApplicationSubmitButtonId: "js-developer-pack-application-submit-button",
              elementThatIsInitiallyHiddenClass: "js-dev-pack-application-initial-form-element",
              emailSelectionContainerId: "js-developer-pack-application-email-selection-container",
              inputId: "js-school-name-search",
              schoolChoice2faErrorElementId: "js-school-choice-2fa-error",
              schoolChoiceAllowlistedDomainsBannerContainerId: "js-chosen-school-has-allowlisted-domains-banner",
              schoolChoiceAllowlistedDomainsBannerSchoolNameId: "js-chosen-school-has-allowlisted-domains-banner-school-name",
              schoolChoiceCaptionElementId: "js-school-choice-caption",
              schoolChoiceDomainsListId: "js-chosen-school-domains-list",
              schoolChoiceFirstAllowlistedDomainId: "js-chosen-school-first-allowlisted-domain",
              schoolChoiceShowMoreDomainsButtonId: "js-chosen-school-domains-show-more",
              suggestedSchoolSelectButtonId: "js-suggested-school-select-button",
              triggerElementClass: "js-school-autocomplete-result-selection",
            },
          ),
          data: {
            test_selector: "autocomplete-schools-helper-react-partial",
          },
        )
      end
    end
  end
end
