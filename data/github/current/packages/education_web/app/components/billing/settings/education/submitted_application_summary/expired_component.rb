# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module SubmittedApplicationSummary
        class ExpiredComponent < BaseComponent
          private

          sig { override.returns(String) }
          def progress_bar_component
            render(Primer::Beta::ProgressBar.new(size: :large)) do |component|
              component.with_item(bg: :done, percentage: 100)
            end
          end

          sig { override.returns(String) }
          def time_words
            "Expired #{time_ago_in_words(submitted_application.expires_at)} ago"
          end
        end
      end
    end
  end
end
