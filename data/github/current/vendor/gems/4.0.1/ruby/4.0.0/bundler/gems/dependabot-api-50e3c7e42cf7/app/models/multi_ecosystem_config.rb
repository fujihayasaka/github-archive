# frozen_string_literal: true

class MultiEcosystemConfig < ApplicationRecord
  has_many :update_configs
  has_many :update_jobs, through: :update_configs

  validates :name, presence: true

  def normalised_name
    name.downcase.gsub(/[^a-z0-9]+/, "_")
  end

  def repo
    update_configs.first&.repo
  end

  def pull_requests
    PullRequest.where(repo_id: repo.id, update_config_id: update_configs.pluck(:id))
  end

  def update_config_siblings
    return [] if update_configs.empty?

    update_configs.first.multi_ecosystem_siblings
  end
end
