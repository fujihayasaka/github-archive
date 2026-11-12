# frozen_string_literal: true

class UpdateJobUnknownError < ApplicationRecord
  belongs_to :update_job
  has_one :update_config, through: :update_job
  has_one :repo, through: :update_config

  validates :update_job, presence: true

  serialize :error_details, coder: JSON
end
