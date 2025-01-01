# typed: true
# frozen_string_literal: true

class IpAllowlistChecks::FormComponent < ApplicationComponent
  attr_reader :owner_type, :owner_id

  def initialize(owner_type:, owner_id:)
    @owner_type = owner_type
    @owner_id = owner_id
  end
end
