# typed: strict
# frozen_string_literal: true

module Business::EnterpriseAgreementDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Business }

  included do
    T.bind(self, T.class_of(Business))
  end

  # Public: Checks whether or not they pay GitHub directly for their service. Businesses with
  # enterprise agreements pay Microsoft, not GitHub directly, so we handle some billing related
  # situations differently for them.
  sig { returns(T::Boolean) }
  def pays_github_directly?
    enterprise_agreements.active.empty?
  end

  sig { returns(T::Boolean) }
  def pays_via_azure_paper?
    enterprise_agreements.active.any?
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def enterprise_agreement_effective_at
    enterprise_agreements.active.is_active
      .where.not(starts_at: nil)
      .order(:starts_at).pick(:starts_at)
  end
end
