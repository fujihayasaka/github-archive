# typed: strict
# frozen_string_literal: true

module Business::LicenseAttributer::BundledLicenseAssignmentDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { Business::LicenseAttributer }

  sig { returns(T.nilable(T::Array[String])) }
  def bundled_license_assignment_emails
    return [] unless volume_licensing_enabled

    @bundled_license_assignment_emails ||= T.let(business.bundled_license_assignments.unassigned_user.pluck(:email), T.nilable(T::Array[String]))
  end

  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def bundled_license_assignment_user_ids(skip_cache: false)
    return [] unless has_active_vss_bundle?
    return @bundled_license_assignment_user_ids if defined?(@bundled_license_assignment_user_ids)

    @bundled_license_assignment_user_ids = T.let(
      fetch_licensee_ids_from_licensify([Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ASSIGNMENT]).select { |id| id.to_s =~ /^\d+$/ }.map(&:to_i),
      T.nilable(T::Array[Integer]),
    )
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  def monolith_bundled_license_assignment_user_ids
    return [] unless volume_licensing_enabled
    return @monolith_bundled_license_assignment_user_ids if defined?(@monolith_bundled_license_assignment_user_ids)

    @monolith_bundled_license_assignment_user_ids = T.let(business.bundled_license_assignments.assigned_user.pluck(:user_id), T.nilable(T::Array[Integer]))
  end

  sig { returns(T::Array[Integer]) }
  def bundled_license_assignment_manual_match_user_ids
    return [] unless has_active_vss_bundle?
    business.bundled_license_assignments.assigned_user.where(manual_match: true).pluck(:user_id)
  end

  sig { returns(T::Hash[Integer, String]) }
  def bundled_license_assignment_assigned_emails
    business.bundled_license_assignments.assigned_user.where(user_id: volume_licensed_user_ids).each_with_object({}) do |id, assigment_emails|
      assigment_emails[id.user_id] = id.email
    end
  end

  sig { params(user_ids: T::Set[Integer]).returns(T::Hash[Integer, String]) }
  def bundled_license_assignment_assigned_emails_for_user_ids(user_ids)
    business.bundled_license_assignments.assigned_user.where(user_id: user_ids).each_with_object({}) do |id, assigment_emails|
      assigment_emails[id.user_id] = id.email
    end
  end

  sig { returns(T::Array[String]) }
  memoize def pending_bundled_license_assignment_emails
    business.pending_bundled_license_assignments.map { |assignment| assignment[:email] }
  end

  sig { returns(T::Boolean) }
  def any_unassigned_user_bundled_license_assignments?
    business.bundled_license_assignments.unassigned_user.exists?
  end
end
