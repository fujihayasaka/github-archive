# typed: true
# frozen_string_literal: true

class Codespaces::ContactUsBannerComponent < ApplicationComponent
  include BillingSettingsHelper

  attr_reader :organization

  def initialize(organization:)
    @organization = organization
  end

  # This should render if the organization needs to contact us to enable codespaces.
  # This renders if the plan would otherwise support enabling codespaces, but we have
  # some restrictions in place, such as to prevent abuse.
  def render?
    Codespaces::OrgPolicy.must_contact_support_to_enable?(org: organization)
  end
end
