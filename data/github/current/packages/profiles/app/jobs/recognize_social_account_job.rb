# typed: strict
# frozen_string_literal: true

class RecognizeSocialAccountJob < ApplicationJob
  extend T::Sig

  queue_as :recognize_social_account
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on ActiveRecord::RecordNotFound

  sig { params(profile_id: Integer).void }
  def perform(profile_id)
    profile = Profile.find(profile_id)
    accounts = T.cast(profile.social_accounts, T::Array[SocialAccount])

    recognition_results = accounts.map { |account| account.recognize(defer_expensive: false) }
    recognized_accounts = recognition_results.map(&:account)
    any_changed = recognized_accounts.zip(accounts).any? { |a, b| a != b }

    if any_changed
      Profile.throttle do
        with_write do
          profile.social_accounts = recognized_accounts
          profile.save
        end
      end
    end

    deferred_write_results = recognition_results.select do |result|
      result.nodeinfo_probe_result&.has_deferred_write?
    end

    if deferred_write_results.any?
      ApplicationRecord::Domain::KeyValues.throttle do
        with_write do
          deferred_write_results.each do |result|
            result.nodeinfo_probe_result&.perform_deferred_write
          end
        end
      end
    end

    failed_results = recognition_results.filter_map(&:nodeinfo_probe_result).select(&:failure?)
    failed_results.each do |failed_result|
      GitHub.logger.info(
        "nodeinfo-probe-failure",
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        **failed_result.details,
      )
    end
  end
end
