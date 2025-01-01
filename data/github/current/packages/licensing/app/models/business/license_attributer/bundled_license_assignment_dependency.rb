# typed: strict
# frozen_string_literal: true

module Business::LicenseAttributer::BundledLicenseAssignmentDependency
  extend T::Sig
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
    return [] unless volume_licensing_enabled
    return @bundled_license_assignment_user_ids if defined?(@bundled_license_assignment_user_ids)

    @bundled_license_assignment_user_ids = T.let(@bundled_license_assignment_user_ids, T.nilable(T::Array[Integer]))
    @bundled_license_assignment_user_ids = business.license_attributer_cache.ids("bundled_license_assignment_user_ids", skip_cache: skip_cache) do
      business.bundled_license_assignments.assigned_user.pluck(:user_id)
    end
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
end
