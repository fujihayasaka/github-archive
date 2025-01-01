# typed: true
# frozen_string_literal: true

class ApiRoutes::EgressAccessDefinition
  attr_reader :verb, :roles
  def initialize(verb, roles)
    @verb = verb
    @roles = roles
  end
end
