# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class OverviewComponent < ApplicationComponent
        sig { params(user: User).void }
        def initialize(user:)
          @user = user
        end

        private

        sig { returns(User) }
        attr_reader :user

        sig { returns(T::Boolean) }
        def render?
          feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
        end

        sig { returns(T::Boolean) }
        def current_coupon_holder?
          current_student? || current_faculty?
        end

        sig { returns(String) }
        def already_applied_coupon_text
          coupon_type = current_student? ? "student" : "faculty"
          "You have a current #{coupon_type} coupon applied. See below for more details."
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
          ordered_application_metadata.exists?
        end

        sig { returns(T::Boolean) }
        def user_has_pending_application?
          ordered_application_metadata.pending.exists?
        end

        sig { returns(T.untyped) }
        memoize def ordered_application_metadata
          user.developer_pack_application_metadata.order(created_at: :desc)
        end
      end
    end
  end
end
