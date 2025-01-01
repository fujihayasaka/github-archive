# typed: true
# frozen_string_literal: true

# Keep track of business account activity
module BusinessUserAccount::Activity
  class << self

    # These cache values are aggressive. The purpose is to make this whole process no-op if a write is not needed.

    # Do not update activity if it's been less than this time since the last update.
    # The reports are 30 or 90 days. An extra few hours is not going to make a difference.
    # This is used to prevent excessive updates to the database.
    USER_ACTIVITY_TTL = 6.hours

    # Cache the business ID for 1 day to avoid excessive database lookups.
    # Orgs do not change businesses often, so this is a reasonable time.
    # The entire org_id -> business_id mapping is about 3mb, so it does not cause excessive storage.
    ORG_BUSINESS_LOOKUP_TTL = 1.day

    # Record user activity for a business from a payload
    # This method is called from instrumentation when a user performs
    # an action that affects their business account.
    # It updates the last business activity timestamp for the user.
    def record_user_activity(payload)
      return if GitHub.single_business_environment?
      return unless FeatureFlag.vexi.enabled?(:business_user_account_record_activity, default: false)

      payload = payload.deep_dup
      payload = prepare_payload(payload)

      business_id = extract_business_id(payload)
      return unless business_id
      if GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get.nil?
        business = Business.find_by(id: business_id)
        return unless business
        GitHub::CurrentTenant.set(business)
      end

      user_id = payload[:user_id]
      actor_id = payload[:actor_id]

      update_user_activity_timestamp(business_id, user_id) if user_id
      update_user_activity_timestamp(business_id, actor_id) if actor_id
    end

    private

    def prepare_payload(payload)
      return payload if (payload[:user_id].present? || payload[:actor_id].present?) && payload[:business_id].present?

      if context = GitHub.context.to_hash
        payload[:user_id] ||= context[:user_id] if context[:user_id].present?
        payload[:actor_id] ||= context[:actor_id] if context[:actor_id].present?
        payload[:business_id] ||= context[:business_id] if context[:business_id].present?
      end

      return payload if (payload[:user_id].present? || payload[:actor_id].present?) && payload[:business_id].present?

      if context = Audit.context.to_hash
        payload[:user_id] ||= context[:user_id] if context[:user_id].present?
        payload[:actor_id] ||= context[:actor_id] if context[:actor_id].present?
        payload[:business_id] ||= context[:business_id] if context[:business_id].present?
      end

      payload
    end

    def update_user_activity_timestamp(business_id, user_id)
      user_key = "business_user_account_activity:#{business_id}:#{user_id}"
      return if GitHub.cache.get(user_key)

      return unless business_user_account = BusinessUserAccount.find_by(business_id: business_id, user_id: user_id)
      updated = ActiveRecord::Base.connected_to(role: :writing) do
        business_user_account.update(last_business_activity_at: Time.now.utc)
      end
      GitHub.cache.set(user_key, true, USER_ACTIVITY_TTL) if updated
    end

    def extract_business_id(payload)
      return payload[:business_id] if payload[:business_id]
      return GitHub::CurrentTenant.get&.id if GitHub.multi_tenant_enterprise?

      if org_id = payload[:org_id]
        org_key = "org_to_business_id:#{org_id}"
        if cached_business_id = GitHub.cache.get(org_key)
          return nil if cached_business_id == "nil"
          return cached_business_id if cached_business_id.present?
        end

        business = Business.from_org_id(org_id)
        if business.present?
          cache_business_id(org_key, business.id)
          business.id
        else
          cache_business_id(org_key, nil)
          nil
        end
      end
    end

    # Caches the business_id or a placeholder ("nil") if no business_id exists
    def cache_business_id(org_key, business_id)
      # If business_id is nil, store "nil" in the cache to avoid future lookups
      if business_id
        GitHub.cache.set(org_key, business_id, ORG_BUSINESS_LOOKUP_TTL)
      else
        GitHub.cache.set(org_key, "nil", ORG_BUSINESS_LOOKUP_TTL)
      end
    end
  end
end
