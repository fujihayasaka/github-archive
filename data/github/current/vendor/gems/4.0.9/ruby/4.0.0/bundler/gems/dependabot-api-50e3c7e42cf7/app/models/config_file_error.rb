# frozen_string_literal: true

class ConfigFileError < ApplicationRecord
  belongs_to :repo

  validates :error_type, presence: true
  validates :repo, presence: true

  serialize :error_details, coder: JSON

  def error_presenter
    ConfigFileErrorPresenter.new(
      error_hash: error_hash,
      config_file_path: repo.config_file_path
    )
  end

  def error_hash
    {
      "error-type" => error_type,
      "error-detail" => error_details,
    }
  end
end
