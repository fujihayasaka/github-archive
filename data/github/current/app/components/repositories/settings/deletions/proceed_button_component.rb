# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Deletions
      class ProceedButtonComponent < ApplicationComponent
        VERIFY_REPO_NWO = "To confirm, type \"%{repo_nwo}\" in the box below"
        STAGES_BUTTON_TEXT = {
          "1" => "I want to delete this repository",
          "2" => "I have read and understand these effects",
          "3" => "Delete this repository"
        }.freeze

        def initialize(repository:, stage:, can_request_bypass: false)
          @repository = repository
          @stage = stage
          @can_request_bypass = can_request_bypass
        end

        private

        attr_reader :repository, :stage, :can_request_bypass

        def button_text
          if can_request_bypass && stage == 3
            "Submit request to delete this repository"
          else
            STAGES_BUTTON_TEXT[stage.to_s]
          end
        end

        memoize def repo_nwo
          repository.name_with_display_owner
        end

        memoize def number_of_stars
          repository.stargazer_count
        end

        def button_type
          if last_stage?
            :submit
          else
            :button
          end
        end

        def last_stage?
          stage == 3
        end

        def next_stage
          stage + 1 unless last_stage?
        end

        def has_stars_or_watchers?
          number_of_stars.positive? || repository.watchers_count.positive?
        end

        def show_verification_input?
          last_stage?
        end

        def verification_label
          VERIFY_REPO_NWO % { repo_nwo: }
        end
      end
    end
  end
end
