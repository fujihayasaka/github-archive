# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MemberFeatureRequestNotificationJob < BatchedJob
  queue_as :member_feature_request_notification
  schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

  retry_on_dirty_exit

  LOOK_BACK_DAYS = 21.days

  # This method accepts a batch of organizations and processes them by iterating
  # over each organization's admins and sending them an email if they have
  # unseen requested features.
  #
  # @param batch [ActiveRecord::Relation] A batch of organizations
  # @param args [Array] Arguments passed to the job
  # @param options [Hash] Options passed to the job
  #
  # @return [ActiveRecord::Relation] The next batch of organizations
  sig { params(batch: T.any(Array, ActiveRecord::Relation), args: T.untyped, options: T.untyped).returns(T.untyped) }
  def process_batch(batch, *args, **options)
    return unless Date.today.thursday?

    batch.each do |entity_id, entity_type|
      entity = entity_type.constantize.find_by(id: entity_id)

      next unless entity
      next if skip_business_or_business_owned_notitication?(entity)
      next if entity.is_a?(Organization) && entity.soft_deleted?

      entity.admins.each do |admin|
        next if entity.is_a?(Organization) && !entity.user_can_receive_email_notifications?(admin)
        next if excluded_by_exclusion_flag?(admin, entity)

        total_feature_request_by_admin = total_by_admin(entity, admin)
        MemberFeatureRequest::Feature.values.each do |feature|
          feature_request_count = total_feature_request_by_admin[feature]
          next if feature_request_count.nil? || feature_request_count.zero?

          last_feature_request = MemberFeatureRequest.where(billing_entity: entity, feature: feature).requested.order(:updated_at).last
          next unless last_feature_request

          if eligible_for_notification?(entity, admin, last_feature_request)
            enqueue_notification(entity, admin, feature, feature_request_count)
          end
        end
      end
    end
  end

  private

  sig { params(batch: T.any(Array, ActiveRecord::Relation), args: T.untyped, options: T.untyped).returns(Integer) }
  def next_batch_offset_item_id(batch, *args, **options)
    batch.map(&:first).max
  end

  sig { params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(T.any(Array, ActiveRecord::Relation)) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    MemberFeatureRequest.where("updated_at > ?", LOOK_BACK_DAYS.ago).
      requested.
      where("billing_entity_id > ?", offset_item_id).
      limit(BATCH_SIZE).
      order(billing_entity_id: :asc).
      distinct.
      pluck(:billing_entity_id, :billing_entity_type)
  end

  sig { params(entity: T.any(Organization, Business), admin: User).returns(T::Hash[MemberFeatureRequest::Feature, Integer]) }
  def total_by_admin(entity, admin)
    MemberFeatureRequest.total_requested_by_feature_since(entity, user_visited_feature_request_page_at(entity, admin))
  end

  sig { params(entity: T.any(Organization, Business), user: User).returns(T.nilable(Time)) }
  def user_visited_feature_request_page_at(entity, user)
    value = Growth::LastActivity::KV.store.get(org_user_visited_feature_request_page_key(entity, user)).value { nil }
    return if value.nil?

    begin
      Time.zone.iso8601(value)
    rescue ArgumentError
      nil
    end
  end

  sig { params(entity: T.any(Organization, Business), user: User).returns(String) }
  def org_user_visited_feature_request_page_key(entity, user)
    case entity
    when Organization
      "user_visited_feature_request_page_#{entity.id}.#{user.id}"
    when Business
      "user_visited_enterprise_policies_copilot_page_#{entity.id}.#{user.id}"
    end
  end

  sig { returns(ActiveRecord::Relation) }
  def organizations_with_requested_features
    Organization.where(id: MemberFeatureRequest.where("updated_at > ?", LOOK_BACK_DAYS.ago).requested.distinct.pluck(:request_entity_id))
  end

  sig { params(entity: T.any(Organization, Business), admin: User, feature_request: MemberFeatureRequest).returns(T::Boolean) }
  def eligible_for_notification?(entity, admin, feature_request)
    return false if duplicated_notification?(entity, admin, feature_request.feature)
    return false unless unread_notification?(entity, admin, feature_request)

    true
  end

  sig { params(entity: T.any(Organization, Business)).returns(T::Boolean) }
  def owned_by_enterprise_account?(entity)
    return true if entity.is_a?(Business)

    entity.business.present?
  end

  sig { params(entity: T.any(Organization, Business)).returns(T::Boolean) }
  def skip_business_or_business_owned_notitication?(entity)
    entity.is_a?(Organization) && entity.business.present?
  end

  sig { params(admin: User, entity: T.any(Organization, Business)).returns(T::Boolean) }
  def excluded_by_exclusion_flag?(admin, entity)
    admin.feature_enabled?(:raf_email_notification_exclusion) ||
      entity.feature_enabled?(:raf_email_notification_exclusion) ||
      (entity.is_a?(Organization) && !!entity.business&.feature_enabled?(:raf_email_notification_exclusion))
  end

  sig { params(entity: T.any(Organization, Business), admin: User, feature: MemberFeatureRequest::Feature, feature_request_count: Integer).returns(T.nilable(ApplicationDeliveryJob)) }
  def enqueue_notification(entity, admin, feature, feature_request_count)
    notification = MemberFeatureRequest::Notification.where(
      feature: feature.to_s,
      entity: entity,
      user: admin
    ).first_or_initialize
    notification.feature_request_count = feature_request_count

    with_write { notification.save! }

    GitHub.dogstats.increment("member_feature_request_notification", tags: [feature.to_s, entity.class.name])
    GlobalInstrumenter.instrument("member_feature_request.notification", { notification_id: notification.id })
  end

  sig { params(entity: T.any(Organization, Business), admin: User, feature: MemberFeatureRequest::Feature).returns(T::Boolean) }
  def duplicated_notification?(entity, admin, feature)
    MemberFeatureRequest::Notification
        .where(feature: feature.to_s, entity: entity, user: admin)
        .where(updated_at: 6.days.ago..)
        .any?
  end

  sig { params(entity: T.any(Organization, Business), admin: User, feature_request: MemberFeatureRequest).returns(T::Boolean) }
  def unread_notification?(entity, admin, feature_request)
    return true unless visited_page_date = user_visited_feature_request_page_at(entity, admin)

    visited_page_date.before?(feature_request.updated_at)
  end
end
