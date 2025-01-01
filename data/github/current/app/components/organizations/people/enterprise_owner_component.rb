# typed: true
# frozen_string_literal: true
class Organizations::People::EnterpriseOwnerComponent < ApplicationComponent
  include Orgs::People::RoleDescriptionMethods
  include Orgs::People::RoleNameMethods

  attr_reader :owner, :organization, :show_admin_stuff

  def initialize(owner:, organization:, show_admin_stuff:)
    @owner = owner
    @organization = organization
    @show_admin_stuff = show_admin_stuff
  end

  # Public: What's this enterprise owner's role?
  #
  # Returns an Organization::Role.
  memoize def role
    Organization::Role.new(organization, owner)
  end
end
