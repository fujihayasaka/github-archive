# typed: true
# frozen_string_literal: true

class ConditionalAccess::IpAllowlist::AccessForbiddenComponent < ApplicationComponent
  attr_reader :target, :ip

  def initialize(target:, ip:)
    @target = target
    @ip = ip
  end

  private

  def target_type_name
    target.is_a?(Business) ? "enterprise" : "organization"
  end
end
