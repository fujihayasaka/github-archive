# typed: true
# frozen_string_literal: true

class TrustTierUpdateEngagedOssJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  schedule interval: 7.days, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit
  queue_as :update_engaged_oss

  def perform
    TrustTierUpdateEngagedOssJob.update_repos
  rescue GitHub::KV::UnavailableError => e
    Failbot.report(e)
    # swallow errors in prod, surface in test environment
    raise if Rails.env.test? #rubocop:disable GitHub/DoNotBranchOnRailsEnv
  end

  def self.update_repos
    TrustTiers::EngagedOss.populate
  end
end
