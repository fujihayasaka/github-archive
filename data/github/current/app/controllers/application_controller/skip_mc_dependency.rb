# typed: true
# frozen_string_literal: true

module ApplicationController::SkipMcDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  # Special error class to track uses of skipmc. See below.
  class SkipmcCalled < StandardError; end

  # Test if cache should be skipped for a request.
  # This is enabled by tacking ?skipmc=<value> onto any URL.
  # Use ?skipmc=1 to skip all cache partitions, or skip a specific partition with
  # ?skipmc=<partition key>.  To skip only the default cache use skipmc=global.
  # Multiple skipmc parameters are allowed: ?skipmc[]=usercontent&skipmc[]=gitrpc
  def skip_mc_check
    if params[:skipmc] || request.env["HTTP_X_SKIP_MC"]
      skip_mc
    end
  end

  private

  # Configures the caches to always miss, causing values to be regenerated and
  # written to cache again.
  # Note: Certain requests (i.e., atom and raw) disable the session, so the
  # staff check fails.
  def skip_mc
    if real_user_site_admin? || employee?

      # Report this skipmc invocation to Failbot, don't raise
      # roll up skipmc needles based on controller/action
      action = params.values_at(:controller, :action).join("#")
      e = SkipmcCalled.new(action)
      e.set_backtrace(caller)
      Failbot.report!(e,
        app: "github-skipmc",
        rollup: Digest::SHA256.hexdigest([e.class.name, action].join("|")),
      )

      skip_mc_partitions.each { |partition| partition.skip = true }
    else
      params.delete(:skipmc)
    end
  end

  # Determines which cache partitions to disable based on the request.
  # - if the value is one of "1", "t", "true", or "all" strings, then skip all cache partitions
  # - if the value is a non-magic string treat it as a partition key and disable a matching partition if one exists
  # - if the value is an array treat the values as partition keys and disable any matching partitions
  def skip_mc_partitions
    arg = params[:skipmc] || request.env["HTTP_X_SKIP_MC"]
    if arg.is_a?(Array)
      arg.map { |key| GitHub.cache_partitions[key.to_sym] }.compact
    elsif %w[1 t true all].include?(arg)
      GitHub.cache_partitions.values
    else
      Array(GitHub.cache_partitions[arg.to_sym]).compact
    end
  end
end
