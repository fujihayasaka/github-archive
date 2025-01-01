# typed: true
# frozen_string_literal: true

require "windbeam_api"

module Dsr
  WINDBEAM_DELETE_PARTICIPANTS = []
  WINDBEAM_EXPORT_PARTICIPANTS = []
  class DisallowedUserDeletionError < StandardError; end
  ExportRequest = Struct.new(:request_id, :status, :created_at)

  def self.delete_user(user)
    return unless user.feature_enabled?(:windbeam_integration)
    return if user.bot?

    if user.never_deletable?
      raise DisallowedUserDeletionError, "Attempted to delete never-deletable user #{user.display_login} (#{user.id})"
    end

    windbeam_client.delete_user(
      user.id,
      user.email.to_s,
      user.analytics_tracking_id,
      user.display_login,
      slug: GitHub::CurrentTenant.get&.slug,
      shortcode: GitHub::CurrentTenant.get&.shortcode,
      identity_id: user.email.to_s,
      identity_type: :EMAIL,
      participants: WINDBEAM_DELETE_PARTICIPANTS
    )
  end

  def self.export_user(user)
    return unless user.feature_enabled?(:windbeam_integration)
    return if user.bot?

    windbeam_client.export_user(
      user.id,
      user.email.to_s,
      user.analytics_tracking_id,
      user.display_login,
      identity_id: user.email.to_s,
      identity_type: :EMAIL,
      slug: GitHub::CurrentTenant.get&.slug,
      shortcode: GitHub::CurrentTenant.get&.shortcode,
      participants: WINDBEAM_EXPORT_PARTICIPANTS
    )
  end

  def self.latest_export_request(user)
    return unless user.feature_enabled?(:windbeam_integration)
    return if user.bot?

    requests = windbeam_client.get_user_requests(user.display_login)

    requests.select { |request| request.request_type == :EXPORT }.max_by(&:created_at)
  end

  def self.get_download_urls(user, request_id)
    return unless user.feature_enabled?(:windbeam_integration)
    return if user.bot?

    exports = windbeam_client.list_exports(request_id)
    exports
      .select { |export| export.status == :COMPLETE }
      .map(&:participant_name)
      .filter_map { |participant| windbeam_client.get_download_url(request_id, participant) }
  end

  def self.windbeam_client
    WindbeamApi::Client.new(GitHub.windbeam_twirp_url, hmac_key: GitHub.windbeam_hmac_key)
  end
end
