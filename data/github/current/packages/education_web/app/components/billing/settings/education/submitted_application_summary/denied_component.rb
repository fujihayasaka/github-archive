# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module SubmittedApplicationSummary
        class DeniedComponent < BaseComponent
          private

          sig { override.returns(String) }
          def progress_bar_component
            render(Primer::Beta::ProgressBar.new(size: :large)) do |component|
              component.with_item(bg: :closed_emphasis, percentage: 100)
            end
          end

          sig { override.returns(String) }
          def time_words
            "Submitted #{time_ago_in_words(submitted_application.created_at)} ago"
          end
        end
      end
    end
  end
end
