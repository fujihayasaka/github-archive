# typed: strict
# frozen_string_literal: true

module Spark
  class ModelRateLimit < ApplicationRecord::Copilot
    self.table_name = "spark_model_rate_limits"

    include ::Users::BelongsToUser
    belongs_to_user_via_domain

    validates :model, presence: true, length: { maximum: 255 }
    validates :user_id, presence: true
  end
end
