# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module SubmittedApplicationSummary
        class RevokedComponent < BaseComponent
          private

          sig { override.returns(String) }
          def progress_bar_component
            render(Primer::Beta::ProgressBar.new(size: :large)) do |component|
              component.with_item(bg: :attention_emphasis, percentage: 100)
            end
          end

          sig { override.returns(String) }
          def time_words
            if submitted_application.denied_at
              "Revoked #{time_ago_in_words(submitted_application.denied_at)} ago"
            else
              ""
            end
          end
        end
      end
    end
  end
end
