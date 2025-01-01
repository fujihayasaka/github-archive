# typed: true
# frozen_string_literal: true

module Organization::GitHubModelsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Organization }

  included do
    T.bind(self, T.class_of(Organization))

    has_many :github_models_access_rules, class_name: "GitHubModels::OrganizationAccessRule", inverse_of: :organization
  end

  # Public: Overrides Configurable::ModelsAccess#instrument_github_models_enablement
  sig { params(actor: User).void }
  def instrument_github_models_enablement(actor:)
    # Audit log:
    instrument :github_models_enabled, actor: actor
  end

  # Public: Overrides Configurable::ModelsAccess#instrument_github_models_disablement
  sig { params(actor: User).void }
  def instrument_github_models_disablement(actor:)
    # Audit log:
    instrument :github_models_disabled, actor: actor
  end
end
