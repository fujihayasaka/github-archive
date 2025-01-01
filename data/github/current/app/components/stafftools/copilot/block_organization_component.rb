# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::BlockOrganizationComponent < ApplicationComponent
  extend T::Sig

  sig { returns(Organization) }
  attr_reader :organization

  sig do
    params(
      organization: Organization,
    ).void
  end
  def initialize(organization:)
    @organization = T.let(organization, Organization)
  end

  sig { returns(T::Boolean) }
  def is_trusted?
    TrustTiers::Tier.for_billable_owner(organization).tier == 1
  end
end
