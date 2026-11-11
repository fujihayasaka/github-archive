# typed: strict
# frozen_string_literal: true

module Codespaces
  class EnablementPolicyInputPresenter

    sig { returns(::Business) }
    attr_reader :business

    sig { returns(Integer) }
    attr_reader :enabled_count

    sig { returns(::Codespaces::BusinessDelegator) }
    attr_reader :codespace_business

    sig { returns(T::Boolean) }
    attr_reader :disable_form

    ALL_ENTITIES = "all_entities"
    SELECTED_ENTITIES = "selected_entities"
    DISABLED = "disabled"

    sig { params(business: ::Business, enabled_count: Integer, disable_form: T::Boolean).void }
    def initialize(business:, enabled_count:, disable_form: false)
      @business = business
      @enabled_count = enabled_count
      @codespace_business = T.let(::Codespaces::BusinessDelegator.new(business), ::Codespaces::BusinessDelegator)
      @disable_form = disable_form
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def serialize
      [
        {
          text: "Enable for all organizations",
          description: "All organizations, including any created in the future, may use GitHub Codespaces.",
          replace_text: "Enable for all organizations",
          confirm_message: "This will enable codespaces for all organizations.",
          checked: codespace_business.codespaces_enabled_for_all_organizations?,
          name: "enablement",
          value: ALL_ENTITIES,
          type: "submit",
          disabled: disable_form
        },
        {
          text: "Enable for specific organizations",
          description: "Only specifically-selected organizations and public repositories may use GitHub Codespaces.",
          replace_text: "Enable for specific organizations",
          confirm_message: "Any codespaces associated with private or internal repositories in the unselected organizations will be deleted.",
          checked: codespace_business.codespaces_enabled_for_selected_organizations?,
          name: "enablement",
          value: SELECTED_ENTITIES,
          type: "submit",
          disabled: disable_form
        },
        {
          text: "Disabled",
          description: "Only public repositories within this enterprise may use GitHub Codespaces.",
          replace_text: "Disabled",
          confirm_message: "All codespaces from internal and private repositories within your enterprise will be deleted.",
          checked: codespace_business.codespaces_disabled?,
          name: "enablement",
          value: DISABLED,
          type: "submit",
          disabled: false # customers should be able to disable codespaces even if they have no payment method
        },
      ]
    end

  end
end
