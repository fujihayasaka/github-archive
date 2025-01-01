# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class OverviewComponent < ApplicationComponent
        # Default number of applications to show per page
        APPLICATIONS_PER_PAGE = 5

        sig { params(user: User, page: Integer, utm_source: T.nilable(String), utm_content: T.nilable(String)).void }
        def initialize(user:, page:, utm_source: nil, utm_content: nil)
          @user = user
          @page = page
          @utm_source = utm_source
          @utm_content = utm_content
        end

        private

        sig { returns(User) }
        attr_reader :user

        sig { returns(Integer) }
        attr_reader :page

        sig { returns(T.nilable(String)) }
        attr_reader :utm_source

        sig { returns(T.nilable(String)) }
        attr_reader :utm_content

        sig { returns(T::Boolean) }
        def render?
          feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
        end

        sig { returns(T::Boolean) }
        def current_coupon_holder?
          current_student? || current_faculty?
        end

        sig { returns(T::Boolean) }
        def dialog_button_disabled?
          if eligible_for_reverification?
            false
          else
            current_coupon_holder? || user_has_pending_application?
          end
        end

        sig { returns(String) }
        def dialog_button_label
          if eligible_for_reverification?
            "Reverify your application"
          else
            "Start an application"
          end
        end

        sig { returns(String) }
        def already_applied_coupon_text
          coupon_type = current_student? ? "student" : "faculty"

          safe_join([
            "You have a current #{coupon_type} coupon applied. ",
            "Find more information on your benefits ",
            link_to("here", "https://github.com/education", class: "Link--inTextBlock"),
            "!",
          ])
        end

        sig { returns(String) }
        def current_pending_application_text
          "You have a current pending application. See below for more details."
        end

        sig { returns(T::Boolean) }
        def current_student?
          user.student_developer_pack_coupon?
        end

        sig { returns(T::Boolean) }
        def current_faculty?
          user.faculty_developer_pack_coupon?
        end

        sig { returns(T::Boolean) }
        def user_has_application?
          ordered_application_metadata_query.exists?
        end

        sig { returns(T::Boolean) }
        def user_has_pending_application?
          ordered_application_metadata_query.pending.exists?
        end

        sig { returns(T::Boolean) }
        memoize def eligible_for_reverification?
          return false unless user.id
          return false unless current_coupon_holder?

          response = discount_requests_client.is_eligible_for_reverification(github_user_id: user.id)
          if response.data
            response.data.is_eligible
          else
            message = response.error&.message || "Unknown error"
            Rails.logger.error("Reverification eligibility check failed: #{response.error.class.name} - #{message}")
            false
          end
        end

        sig { returns(T::Boolean) }
        memoize def spammy_suspended_trade_restrictions_edu_blocked?
          return false unless user.id
          return true if user.spammy? || user.suspended? || user.has_any_trade_restrictions?

          response = discount_requests_client.is_blocked(github_user_id: user.id)

          if response.data
            response.data.is_blocked
          else
            message = response.error&.message || "Unknown error"
            Rails.logger.error("Blocked user check failed: #{response.error.class.name} - #{message}")
            false
          end
        end

        sig { returns(T.untyped) }
        memoize def ordered_application_metadata
          ordered_application_metadata_query
            .paginate(page: page, per_page: APPLICATIONS_PER_PAGE)
        end

        sig { returns(Integer) }
        def total_pages
          ordered_application_metadata.total_pages
        end

        sig { returns(T::Boolean) }
        def show_pagination?
          total_pages > 1
        end

        sig { returns(T.untyped) }
        memoize def ordered_application_metadata_query
          user.developer_pack_application_metadata.order(created_at: :desc)
        end

        sig { returns(T::Hash[Symbol, String]) }
        def pagination_params
          {
            controller: "settings/education/benefits",
            action: "index",
          }
        end

        sig { returns(::Education::Twirp::DiscountRequestsClient) }
        memoize def discount_requests_client
          ::Education::Twirp::DiscountRequestsClient.new(user:)
        end
      end
    end
  end
end
