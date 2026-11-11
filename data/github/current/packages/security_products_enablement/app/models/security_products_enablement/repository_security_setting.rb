# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class RepositorySecuritySetting < ApplicationRecord::Domain::SecurityProductsEnablement
    # NOTE: This model is not visible to the audit log yet, it just instruments events for observability.
    include Instrumentation::Model

    self.table_name = "repository_security_settings"
    self.primary_key = %w[repository_id feature]

    after_commit :instrument_create_setting, on: :create
    after_commit :instrument_update_setting, on: :update, if: :saved_changes?
    after_destroy_commit :instrument_delete_setting

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain
    validates :repository, presence: true
    validates :feature, uniqueness: { scope: :repository_id }

    enum :feature, {
      dependency_graph: 1
    },
    validate: true

    enum :state, {
      enabled: 1
    },
    validate: true

    private

    sig { returns(String) }
    def event_prefix
      "repository_security_setting"
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      {
        repository_security_setting_id: id,
        repository_id: repository_id,
        feature: feature,
        state: state,
      }
    end

    sig { void }
    def instrument_create_setting
      instrument :create
    end

    sig { void }
    def instrument_update_setting
      instrument :update
    end

    sig { void }
    def instrument_delete_setting
      instrument :delete
    end
  end
end
