# typed: true
# frozen_string_literal: true

# rubocop:disable ViewComponent/ComponentsHaveUnitTests
# tests are here: test/components/repositories/settings/detaches/proceed_button_component_test.rb

module Repositories
  module Settings
    module Detaches
      class ProceedButtonComponent < ApplicationComponent
        VERIFY_REPO_NWO = "To confirm, type \"%{repo_nwo}\" in the box below"
        STAGES_BUTTON_TEXT = {
          "1" => "I want to leave fork network",
          "2" => "I have read and understand these effects",
          "3" => "Leave fork network"
        }.freeze

        def initialize(repository:, stage:)
          @repository = repository
          @stage = stage
        end

        private

        attr_reader :repository, :stage

        def button_text
          STAGES_BUTTON_TEXT[stage.to_s]
        end

        memoize def repo_nwo
          repository.name_with_display_owner
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
