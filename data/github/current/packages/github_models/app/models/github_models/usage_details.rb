# typed: true
# frozen_string_literal: true

class GitHubModels::UsageDetails < ApplicationRecord::Domain::GitHubModels
  include GitHubModels::IUsageDetails

  self.table_name = "models_usage_details"

  API_INSTRUMENTATION_PREFIX = "github_models.api."

  belongs_to :user, class_name: "::User", required: true, inverse_of: :github_models_usage_details

  after_save :instrument_save

  validates :auths_count, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  sig { params(user_id: T.any(Integer, String)).returns(Integer) }
  def self.auths_count_for_user_id(user_id)
    record = find_by(user_id: user_id)
    record&.auths_count || 0
  end

  sig { params(user_id: Integer).returns(T.nilable(GitHubModels::IUsageDetails)) }
  def self.create_or_update(user_id)
    report_on_failure = -> {
      GitHub.dogstats.increment(API_INSTRUMENTATION_PREFIX + "auth_count_record_failure")
      nil
    }

    retry_on_find_or_create_error(on_max_retry: report_on_failure) do
      record = find_by(user_id: user_id)

      if record.present?
        record.increment!(:auths_count, touch: true)
      else
        create(user_id: user_id, auths_count: 1)
      end
    end
  end

  private

  def instrument_save
    return unless saved_changes.key?(:auths_count)
    GlobalInstrumenter.instrument("github_models_usage_details.update", user: user, auths_count: auths_count)
  end
end
