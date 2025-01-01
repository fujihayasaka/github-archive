# typed: true
# frozen_string_literal: true

class ApiRoutes::EgressRole
  attr_reader :name, :permissions
  def initialize(name, permissions)
    @name = name
    if permissions.length > 1
      permissions.delete("metadata")
    end
    @permissions = permissions
  end
end
