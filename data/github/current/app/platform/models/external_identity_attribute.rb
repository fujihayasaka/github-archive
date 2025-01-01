# typed: true
# frozen_string_literal: true

class Platform::Models::ExternalIdentityAttribute
  attr_reader :identity
  attr_reader :attribute

  def initialize(identity, attr)
    @identity = identity
    @attribute = attr
  end
end
