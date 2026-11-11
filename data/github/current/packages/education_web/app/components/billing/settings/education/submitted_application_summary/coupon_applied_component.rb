# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module SubmittedApplicationSummary
        class CouponAppliedComponent < BaseComponent
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
            return "Does not expire" if submitted_application.expires_at.nil?
            "Expires in #{time_ago_in_words(submitted_application.expires_at)}"
          end

          sig { returns(Integer) }
          def time_passed_in_percentage
            return 0 if submitted_application.expires_at.nil?

            total_days = (T.must(submitted_application.expires_at) - submitted_application.approved_at).to_i / 1.day
            return 100 if total_days <= 0

            days_since_approved = (Time.current - submitted_application.approved_at).to_i / 1.day
            ((days_since_approved.to_f / total_days) * 100).ceil.clamp(0, 100)
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
