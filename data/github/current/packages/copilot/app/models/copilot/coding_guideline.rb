# typed: strict
# frozen_string_literal: true

module Copilot
  class CodingGuideline < ApplicationRecord::Copilot
    extend T::Sig

    MAX_PER_REPO = 30
    PROMPT_CHAR_LIMIT = 600

    self.table_name = "copilot_coding_guidelines"
    self.strict_loading_by_default = true

    belongs_to :repository, strict_loading: false
    has_many :paths,
      class_name: "Copilot::CodingGuidelinePath",
      strict_loading: false,
      foreign_key: :copilot_coding_guideline_id,
      inverse_of: :copilot_coding_guideline

    accepts_nested_attributes_for :paths, allow_destroy: true, reject_if: :all_blank

    validates :name, presence: true, length: { maximum: 200 }, uniqueness: { scope: :repository_id }
    validates :description, presence: true, length: { maximum: PROMPT_CHAR_LIMIT }
    validates :example_code_violations, length: { maximum: PROMPT_CHAR_LIMIT }

    sig { params(repository_id: T.nilable(Integer)).returns(T::Array[T::Hash[T.untyped, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
    def self.references_for(repository_id)
      repo = Repository.find_by(id: repository_id)
      return [] unless repo

      self.where(repository: repo, enabled: true)
        .limit(Copilot::CodingGuideline::MAX_PER_REPO)
        .map do |guideline|
          {
            type: "github.coding_guideline",
            id: "#{repo.name_with_display_owner}-#{guideline.id}",
            data: {
              id: guideline.id,
              type: "coding-guideline",
              repositoryId: repo.id,
              name: guideline.name,
              description: guideline.description,
              filePatterns: guideline.paths.map { |path| path.path }
            }
          }
        end
    end
  end
end
