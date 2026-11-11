# typed: true
# frozen_string_literal: true

module ApplicationController::RemoteCacheDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  private

  def remote_cache_override_check
    value = params[:remote_cache] || request.env["HTTP_X_REMOTECACHE_OVERRIDE"]
    return unless value

    if real_user_site_admin? || employee?
      case value.to_s
      when "skip"
        GH.context.remote_cache_override = GitHub::RemoteCacheOverride::Skip
      when "refresh"
        GH.context.remote_cache_override = GitHub::RemoteCacheOverride::ForceRefresh
      end
    else
      params.delete(:remote_cache)
    end
  end
end
