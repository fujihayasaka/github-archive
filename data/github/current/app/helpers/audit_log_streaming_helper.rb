# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/RailsViewRenderLiteral

module AuditLogStreamingHelper
  extend T::Helpers

  def hec_feature_enabled?(business)
    GitHub.flipper[:audit_log_streaming_hec_option].enabled?(business) && !GitHub.enterprise?
  end
end
