# typed: true
# frozen_string_literal: true

class AzureModels::UsageDetails < ApplicationRecord::Domain::Integrations # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  self.table_name = "azure_models_usage_details"

  # rubocop:todo Rails/InverseOf
  belongs_to :user, class_name: "::User", foreign_key: :user_id, strict_loading: false
  # rubocop:enable Rails/InverseOf

  after_save :instrument_save

  def self.auths_count_for_user_id(user_id)
    record = find_by(user_id: user_id)
    record&.auths_count || 0
  end

  def instrument_save
    return unless saved_changes.key?(:auths_count)

    GlobalInstrumenter.instrument("azure_models_usage_details.update", user: user, auths_count: auths_count)
  end
end
