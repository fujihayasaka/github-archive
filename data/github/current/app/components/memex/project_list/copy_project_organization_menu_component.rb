# typed: true
# frozen_string_literal: true

class Memex::ProjectList::CopyProjectOrganizationMenuComponent < ApplicationComponent
  delegate :avatar_for, to: :helpers

  def initialize(owners:, default_owner:)
    @owners = owners
    @default_owner = default_owner
  end
end
