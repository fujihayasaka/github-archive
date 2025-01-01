# typed: true
# frozen_string_literal: true

class ConditionalAccess::ExternalConditionalAccess::AccessForbiddenComponent < ApplicationComponent
  attr_reader :target, :idp_message

  def initialize(target:, message:)
    @target = target
    @idp_message = message
  end
end
