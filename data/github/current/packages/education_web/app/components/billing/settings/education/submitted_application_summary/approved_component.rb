# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module SubmittedApplicationSummary
        class ApprovedComponent < BaseComponent
          private

          sig { override.returns(String) }
          def progress_bar_component
            render(Primer::Beta::ProgressBar.new(size: :large)) do |component|
              component.with_item(bg: :done, percentage: time_passed_in_percentage)
              component.with_item(bg: :success_emphasis, percentage: time_remaining_in_percentage)
            end
          end

          sig { override.returns(String) }
          def time_words
            "Expires in #{time_ago_in_words(submitted_application.expires_at)}"
          end

          sig { returns(Integer) }
          def time_passed_in_percentage
            days_since_approved = (Time.current - submitted_application.approved_at).to_i / 1.day
            days_until_expiration = (submitted_application.expires_at - Time.current).to_i / 1.day
            ((days_since_approved / days_until_expiration) * 100).ceil
          end

          sig { returns(Integer) }
          def time_remaining_in_percentage
            100 - time_passed_in_percentage
          end
        end
      end
    end
  end
end
