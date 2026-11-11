# typed: true
# frozen_string_literal: true

module Api::App::RemoteCacheDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  private

  # Internal: Check for the remote_cache query parameter or X-RemoteCache-Override
  # header and override the remote cache behavior for the current request when
  # the caller is a staff member. Non-staff callers have the parameter silently
  # stripped.
  #
  # Accepted values: "skip" (bypass cache) or "refresh" (force-refresh all keys).
  #
  # This mirrors ApplicationController::RemoteCacheDependency for the Sinatra API
  # layer and is intended for debugging purposes only.
  #
  # Returns nothing.
  def remote_cache_override_check
    value = params[:remote_cache] || request.env["HTTP_X_REMOTECACHE_OVERRIDE"]
    return unless value

    if current_user&.site_admin? || request_authorized_by_employee?
      case value.to_s
      when "skip"
        GH.context.remote_cache_override = GitHub::RemoteCacheOverride::Skip
      when "refresh"
        GH.context.remote_cache_override = GitHub::RemoteCacheOverride::ForceRefresh
      end
    else
      params.delete("remote_cache")
    end
  end
end
