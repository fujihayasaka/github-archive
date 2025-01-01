# typed: true
# frozen_string_literal: true

class RegexValidationController < ApplicationController
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency

  before_action :require_body
  allow_verified_fetch only: [:validate_regex]

  sig { void }
  def validate_regex # rubocop:todo GitHub/UseRestfulActions
    type = params.require(:type)

    pattern = @body["pattern"]

    valid = case type
    when "pattern"
      Regex::RE2Helper.new.is_valid?(pattern)
    when "value"
      Regex::RE2Helper.new.matches?(@body["value"], pattern)
    end

    render json: { valid: valid }
  end

  sig { returns(Symbol) }
  def resource_for_conditional_access # rubocop:todo GitHub/UseRestfulActions
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  sig { returns(Symbol) }
  def target_for_conditional_access # rubocop:todo GitHub/UseRestfulActions
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  private

  sig { void }
  def require_body
    begin
      @body = JSON.parse(request&.body.read)
    rescue JSON::ParserError, TypeError
      render json: { valid: false }, status: :bad_request
    end
  end
end
