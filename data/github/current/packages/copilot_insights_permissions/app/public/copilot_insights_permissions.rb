# typed: strict
# frozen_string_literal: true

require_relative "copilot_insights_permissions/permission_check"

module CopilotInsightsPermissions
  extend T::Helpers
  include GitHub::Memoizer

  private

  sig { params(business: T.nilable(Business), user: T.nilable(User)).returns(T::Boolean) }
  def copilot_insights_usage_available?(business:, user:)
    return false if business.nil? || user.nil?

    PermissionCheck.new(business: business, user: user).copilot_insights_usage_feature_available?
  end

  sig { params(business: T.nilable(Business), user: T.nilable(User)).returns(T::Boolean) }
  def copilot_insights_code_generation_available?(business:, user:)
    return false if business.nil? || user.nil?

    PermissionCheck.new(business: business, user: user).copilot_insights_code_generation_feature_available?
  end
end
