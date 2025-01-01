# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::OrganizationAccessDetailComponent < ApplicationComponent
  extend T::Sig

  sig { returns(Copilot::Organization) }
  attr_reader :copilot_organization

  sig { returns(::Organization) }
  attr_reader :organization

  sig { params(organization: ::Organization).void }
  def initialize(organization)
    @organization         = organization
    @copilot_organization = T.let(Copilot::Organization.new(organization), Copilot::Organization)
  end
end
