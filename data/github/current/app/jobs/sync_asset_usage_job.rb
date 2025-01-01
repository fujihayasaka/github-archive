# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This is an abstract class that should not be used directly.
# Inherit from this class, e.g., SyncAssetUsageSchedulerJob

class SyncAssetUsageJob < ApplicationJob
  RETRYABLE_ERRORS = [
    Aqueduct::Worker::JobKilled,
    Aws::Errors::ServiceError,
    Seahorse::Client::NetworkingError,
  ].freeze

  def self.read_int_from_env(key, default)
    val = ENV["GITHUB_LFS_" + key].to_i.abs
    val.zero? ? default : val
  end

  LOG_BUCKET_NAME = "github-cloud-logs"
  LOG_KEY_PREFIX = "s3/"

  def perform
    raise NotImplementedError
  end

  def log_scanner
    Asset::LogScanner.new(GitHub.s3_primary_client, LOG_BUCKET_NAME, LOG_KEY_PREFIX)
  end

  def stat_dist(suffix, value)
    GitHub.dogstats.distribution("s3_usage.dist.#{suffix}", value)
  end

  def stat_time(suffix, &block)
    GitHub.dogstats.distribution_time("s3_usage.dist.#{suffix}.time", &block)
  end

  def stat_gauge(suffix, value)
    GitHub.dogstats.gauge("s3_usage.#{suffix}", value)
  end

  def stat_incr(suffix)
    GitHub.dogstats.increment("s3_usage.#{suffix}")
  end

  def stat_count(suffix, value)
    GitHub.dogstats.count("s3_usage.#{suffix}", value)
  end
end
