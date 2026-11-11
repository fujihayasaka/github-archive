# typed: strict
# frozen_string_literal: true

# User model extensions relevant to GitHub's Education integrations.
module User::EducationDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_many(
      :developer_pack_application_metadata,
      class_name: "EducationDeveloperPackApplicationMetadata",
      dependent: :destroy,
    )
  end

  # Checks if the user has an education coupon code on their account
  #
  # Returns true if education, otherwise false
  sig { returns(T::Boolean) }
  def education?
    coupons.education.any? || emails.any?(&:education?)
  end

  # Checks if the user has an student pack coupon code on their account
  #
  # Returns true if student pack coupon is active, otherwise false
  sig { returns(T::Boolean) }
  def student_developer_pack_coupon?
    return false unless has_an_active_coupon?

    /\A#{Coupon::STUDENT_DEVELOPER_PACK_NAME}/.match?(T.must(coupon).code)
  end

  # Checks if the user has a faculty pack coupon code on their account
  #
  # Returns true if faculty pack coupon is active, otherwise false
  sig { returns(T::Boolean) }
  def faculty_developer_pack_coupon?
    return false unless has_an_active_coupon?

    /\A#{Coupon::FACULTY_DEVELOPER_PACK_NAME}/.match?(T.must(coupon).code)
  end

  # Checks if the user has an .edu email
  sig { returns(T::Boolean) }
  def edu_email?
    emails.any?(&:education?)
  end
end
