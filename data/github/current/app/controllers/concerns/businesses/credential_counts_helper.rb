# typed: true
# frozen_string_literal: true

module Businesses::CredentialCountsHelper
  extend ActiveSupport::Concern

  private

  def fetch_credential_counts(business)
    {
      fine_grained_pat_count: business.fine_grained_pat_count,
      fine_grained_pat_count_capped: business.fine_grained_pat_count_capped?,
      classic_pat_count: business.classic_pat_count,
      classic_pat_count_capped: business.classic_pat_count_capped?,
      ssh_key_count: business.ssh_key_count,
      ssh_key_count_capped: business.ssh_key_count_capped?,
      oauth_application_access_token_count: business.oauth_application_access_token_count,
      oauth_application_access_token_count_capped: business.oauth_application_access_token_count_capped?,
      timed_out: false
    }
  rescue ActiveRecord::QueryAborted, GitHub::RequestDurationManager::TimeBudgetIsOverError
    {
      timed_out: true
    }
  end
end
