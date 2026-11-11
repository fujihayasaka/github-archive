# typed: strict
# frozen_string_literal: true

# Background job that computes OAuth enterprise limit data for an (app_id, user_id)
# pair and writes the result to the oauth_enterprise_limits table.
#
# Enqueued by:
# - OauthAccess after_commit hooks (token creation)
# - OauthApplicationApproval lifecycle hooks (approval changes)
# - Backfill transitions
class OauthEnterpriseLimitJob < ApplicationJob
  use_primaries ApplicationRecord::Domain::Authentication
  use_replicas ApplicationRecord::Mysql1, ApplicationRecord::IamAbilities

  queue_as :oauth_enterprise_limits
  retry_on_recoverable_exceptions
  discard_on ArgumentError
  retry_on_dirty_exit

  sig { params(app_id: Integer, user_id: T.nilable(Integer), action: String, organization_id: T.nilable(Integer)).void }
  def perform(app_id:, user_id: nil, action: "write", organization_id: nil)
    case action
    when "write"
      raise ArgumentError, "user_id is required for write action" if user_id.nil?
      OauthEnterpriseLimitWriter.write_for(app_id:, user_id:)
    when "remove"
      raise ArgumentError, "user_id is required for remove action" if user_id.nil?
      OauthEnterpriseLimitWriter.remove_for(app_id:, user_id:)
    when "approval_change"
      raise ArgumentError, "organization_id is required for approval_change action" if organization_id.nil?
      OauthEnterpriseLimitWriter.write_for_approval_change(app_id:, organization_id:)
    else
      raise ArgumentError, "Unknown action: #{action}"
    end
  end
end
