# frozen_string_literal: true

class UpdateJobWarning < ApplicationRecord
  belongs_to :update_job
  has_one :update_config, through: :update_job
  has_one :repo, through: :update_config

  validates :warn_type, presence: true
  validates :warn_title, presence: true
  validates :warn_description, presence: false

  validates :update_job, presence: true
  validates :warn_type, uniqueness: { scope: %i(update_job warn_title warn_description) }

  def warning_presenter
    UpdateJobWarningPresenter.new(
      warning_hash: warning_hash,
      update_job: update_job
    )
  end

  def warning_hash
    {
      "warn_type" => warn_type,
      "warn_title" => warn_title,
      "warn_description" => warn_description,
    }
  end
end
