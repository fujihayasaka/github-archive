# typed: true
# frozen_string_literal: true

class TrustTierUpdateEngagedOssJob < ApplicationJob
  schedule interval: 7.days, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit
  queue_as :update_engaged_oss

  def perform
    with_write { TrustTiers::EngagedOss.populate }
  rescue GitHub::KV::UnavailableError => e
    Failbot.report(e)
    # swallow errors in prod, surface in test environment
    raise if Rails.env.test? #rubocop:disable GitHub/DoNotBranchOnRailsEnv
  end
end
