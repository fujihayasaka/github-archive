# typed: true
# frozen_string_literal: true

class Platform::Models::OrganizationAdminInfo
  attr_reader :org

  def initialize(org)
    @org = org
  end
end
