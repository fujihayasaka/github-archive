# typed: strict
# frozen_string_literal: true

module Spark
  class ModelRateLimit < ApplicationRecord::Copilot
    self.table_name = "spark_model_rate_limits"

    belongs_to :user

    validates :model, presence: true, length: { maximum: 255 }
    validates :user_id, presence: true
  end
end
