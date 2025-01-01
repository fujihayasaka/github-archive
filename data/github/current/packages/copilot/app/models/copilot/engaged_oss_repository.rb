# typed: true
# frozen_string_literal: true

module Copilot
  class EngagedOssRepository < ApplicationRecord::Copilot
    include Copilot::Metrics

    self.table_name = "copilot_engaged_oss_repositories"
    self.strict_loading_by_default = true

    belongs_to :repository, class_name: "::Repository", strict_loading: false
    belongs_to :language_name, class_name: "::LanguageName", strict_loading: false

    validates :fork_count, presence: true
    validates :language_name, presence: true
    validates :last_pushed_at, presence: true
    validates :license_id, presence: true
    validates :rank, presence: true
    validates :repository, presence: true
    validates :stargazer_count, presence: true

    validates :license_id, inclusion: { in: License.valid_license_ids }

    def self.from_repository(repository, rank: 0)
      Copilot::EngagedOssRepository.new(
        repository_id: repository.id,
        language_name_id: repository.primary_language_name_id,
        fork_count: repository.public_fork_count.to_i,
        last_pushed_at: repository.pushed_at || repository.created_at,
        license_id: repository.repository_licenses.first&.license_id,
        stargazer_count: repository.stargazer_count,
        rank: rank
      )
    end

    def to_i
      id
    end
  end
end
