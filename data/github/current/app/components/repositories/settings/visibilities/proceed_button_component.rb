# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Visibilities
      class ProceedButtonComponent < ApplicationComponent
        VERIFY_REPO_NWO = "To confirm, type \"%{repo_nwo}\" in the box below"
        VERIFY_NUMBER_OF_STARS = "To confirm, type the number of stars on this repository in the "\
          "box below"
        STAGES_BUTTON_TEXT = {
          "1" => "I want to make this repository %{new_visibility}",
          "2" => "I have read and understand these effects",
          "3" => "Make this repository %{new_visibility}"
        }.freeze

        def initialize(repository:, new_visibility:, stage:)
          @repository = repository
          @new_visibility = new_visibility
          @stage = stage
        end

        private

        attr_reader :repository, :new_visibility, :stage

        def button_text
          STAGES_BUTTON_TEXT[stage.to_s] % { new_visibility: }
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
          last_stage? && number_of_stars.positive?
        end

        def verification_label
          if new_visibility == "public"
            VERIFY_REPO_NWO % { repo_nwo: }
          else
            VERIFY_NUMBER_OF_STARS
          end
        end
      end
    end
  end
end
