# typed: true
# frozen_string_literal: true

class HydroDiscountRequestChangeJob < HydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_discount_request_change
  retry_on_dirty_exit

  REVOKED_REASON = "<ul><li>Your access has been revoked.</li></ul>".freeze

  sig { void }
  def perform
    return unless GitHub.flipper[:education_dev_pack_application_hydro_job].enabled?
    return unless target_application_metadata.present?

    if state == :REJECTED || state == :REVOKED
      with_write do
        T.must(target_application_metadata).update(
          denied_at: Time.now,
          rejection_reason:,
        )
      end
    elsif state == :APPROVED
      with_write do
        T.must(target_application_metadata).update(approved_at: Time.now)
      end
    end
  end

  private

  sig { returns(T.nilable(EducationDeveloperPackApplicationMetadata)) }
  memoize def target_application_metadata
    return unless external_discount_request_id.present?
    return unless user.present?

    metadata = ::EducationDeveloperPackApplicationMetadata.find_by(external_discount_request_id:, user:)
    return metadata if metadata.present?

    # Create a new record if one doesn't exist
    with_write do
      ::EducationDeveloperPackApplicationMetadata.create!(
        user:,
        external_discount_request_id:,
        application_type: application_type,
        applied_at: applied_at
      )
    end
  end

  sig { returns(Symbol) }
  def application_type
    type = message.dig(:discount_request, :type)
    if type == :FACULTY_INDIVIDUAL || type == :FACULTY_ORGANIZATION
      :faculty
    else
      :student # Default to student for all other cases
    end
  end

  sig { returns(DateTime) }
  def applied_at
    created_at = message.dig(:discount_request, :created_at)
    return DateTime.now unless created_at.present?

    DateTime.parse(created_at.to_s)
  rescue
    DateTime.now
  end

  sig { returns(T.nilable(Integer)) }
  memoize def external_discount_request_id
    message.dig(:discount_request, :id)
  end

  sig { returns(T.nilable(User)) }
  memoize def user
    return unless applicant_id.present?

    ::User.find_by(id: applicant_id)
  end

  sig { returns(T.nilable(Integer)) }
  memoize def applicant_id
    message.dig(:actor, :github_id)
  end

  sig { returns(Symbol) }
  def state
    message[:type]
  end

  sig { returns(T.nilable(String)) }
  def rejection_reason
    return REVOKED_REASON if state == :REVOKED

    reasons = message.dig(:discount_request, :rejection_reasons)
    return unless reasons.present?

    [
      "<ul>",
      reasons.map { |reason| "<li>#{reason}</li>" }.join,
      "</ul>",
    ].join
  end
end
