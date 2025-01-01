# typed: strict
# frozen_string_literal: true

module Education::DeveloperPackApplication::SchoolHelper
  sig { params(school: T.untyped, user_has_two_factor_auth_enabled: T::Boolean).returns(T::Boolean) }
  def user_needs_2fa_turned_on?(school:, user_has_two_factor_auth_enabled:)
    school_cares_about_2fa?(school:) && !user_has_two_factor_auth_enabled
  end

  sig { params(school: T.untyped).returns(T::Boolean) }
  def school_cares_about_2fa?(school:)
    school["two_factor_required"] == true
  end

  sig { params(school: T.untyped).returns(T::Array[T.untyped]) }
  def email_domains(school:)
    Array.wrap(school["email_domains"]).map do |domain|
      [
        domain.domain,
        domain.ignores_distance_limit,
        domain.domain_kind,
        domain.state,
      ]
    end
  end

  sig { params(school: T.untyped).returns(T::Boolean) }
  def user_too_far_from_school?(school:)
    max_miles = Array.wrap(school["campuses"]).first&.max_miles_to_be_considered_near.to_i

    result = Array.wrap(school["campuses"]).all? do |campus|
      campus["distance_from_ip"].to_i > max_miles
    end

    school_cares_about_distance?(school:) && result
  end

  sig { params(school: T.untyped).returns(T::Boolean) }
  def school_cares_about_distance?(school:)
    school["override_distance_limit"] == false
  end

  sig { params(school: T.untyped).returns(T.nilable(T::Boolean)) }
  def school_allows_file_uploads?(school:)
    school["camera_required"] == false &&
      school["override_distance_limit"] == false &&
      !user_too_far_from_school?(school:)
  end

  sig { params(school: T.untyped, user_verified_emails: T::Array[String]).returns(T::Boolean) }
  def user_has_email_for_school?(school:, user_verified_emails:)
    email_domains_for_school = email_domains(school:).transpose.first

    return true if email_domains_for_school.blank?

    user_verified_emails.any? { |email| email.end_with?(*email_domains_for_school) }
  end
end
