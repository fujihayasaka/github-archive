# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Persists nudge interactions to dotcom MySQL (the user's
  # InProductMessagingSubscription metadata) so that server-side eligibility
  # and throttling logic -- such as `User#nudge_exceeds` and
  # `User#interacted_with_a_nudge` -- can read them back on subsequent
  # requests.
  #
  # This is INTENTIONALLY separate from Hydro / the data warehouse. The React
  # nudge partial fires its own client-side `visibleEvent` / `clickEvent` /
  # `dismissEvent` payloads into Hydro for analytics; those are fire-and-forget
  # and cannot be read back from the monolith. The "copy" written here exists
  # solely so the backend can make targeting decisions. Keep both -- they serve
  # different consumers.
  class NudgeMemory
    sig { returns(::User) }
    attr_reader :user

    sig { params(user: ::User).void }
    def initialize(user)
      @user = user
    end

    # Public: Increment the impression count for a specific nudge ID
    # and update the last impression timestamp
    #
    # id - Symbol or String representing the unique identifier for the nudge
    # group - Symbol representing the group of the nudge
    #
    # Returns the updated count
    sig do
      params(
        id: T.nilable(T.any(String, Symbol)),
        group: T.nilable(Symbol),
        enterprise_id: T.nilable(T.any(String, Symbol, Integer)),
        org_id: T.nilable(T.any(String, Symbol, Integer))
      ).returns(Integer)
    end
    def save_a_copy_of_impression_analytics_to_dotcom(id: nil, group: nil, enterprise_id: nil, org_id: nil)
      namespace_params = [enterprise_id, org_id].compact
      Kernel.raise ArgumentError, "Can only provide one of enterprise_id: or org_id: parameters" if namespace_params.length > 1

      ActiveRecord::Base.connected_to(role: :writing) do
        subscription = find_or_create_in_product_messaging_subscription

        current_metadata = subscription.metadata || {}
        current_metadata["impressions"] ||= {}

        # Clean up old impressions
        cutoff_time = User::NudgeInteractionDependency::NUDGE_INTERACTION_RETENTION_DAYS.days.ago
        current_metadata["impressions"].delete_if do |_, data|
          updated_at = data["updated_at"]
          next false unless updated_at
          Time.parse(updated_at) < cutoff_time
        end

        # Add/update current impression
        current_metadata["impressions"][id.to_s] ||= {
          "count" => 0,
          "updated_at" => nil
        }

        if group
          current_metadata["impressions"][id.to_s]["group"] = group.to_s
        end

        if enterprise_id
          current_metadata["impressions"][id.to_s]["enterprise"] = enterprise_id.to_s
        end

        if org_id
          current_metadata["impressions"][id.to_s]["org"] = org_id.to_s
        end

        # Increment the impression count but don't allow it to get infinitely high
        current_metadata["impressions"][id.to_s]["count"] = [current_metadata["impressions"][id.to_s]["count"] + 1, 9999].min
        current_metadata["impressions"][id.to_s]["updated_at"] = Time.current.iso8601

        subscription.metadata = current_metadata
        subscription.save!
        current_metadata["impressions"][id.to_s]["count"]
      end
    end

    # Public: Record a click for a specific nudge ID and clean up old click records
    #
    # id - Symbol or String representing the unique identifier for the nudge
    # group - Symbol representing the group of the nudge
    # enterprise_id - String representing the enterprise ID (optional)
    # org_id - String representing the organization ID (optional)
    #
    # Returns nothing
    sig do
      params(
        id: T.nilable(T.any(String, Symbol)),
        group: T.nilable(Symbol),
        enterprise_id: T.nilable(T.any(String, Symbol, Integer)),
        org_id: T.nilable(T.any(String, Symbol, Integer))
      ).returns(NilClass)
    end
    def save_a_copy_of_click_analytics_to_dotcom(id: nil, group: nil, enterprise_id: nil, org_id: nil)
      ActiveRecord::Base.connected_to(role: :writing) do
        subscription = find_or_create_in_product_messaging_subscription
        current_metadata = subscription.metadata || {}
        current_metadata["clicks"] ||= {}

        # Add the new click
        current_metadata["clicks"][id.to_s] = {
          "updated_at" => Time.current.iso8601
        }

        if group
          current_metadata["clicks"][id.to_s]["group"] = group.to_s
        end

        if enterprise_id
          current_metadata["clicks"][id.to_s]["enterprise"] = enterprise_id.to_s
        end

        if org_id
          current_metadata["clicks"][id.to_s]["org"] = org_id.to_s
        end

        # Remove old clicks
        cutoff_time = User::NudgeInteractionDependency::NUDGE_INTERACTION_RETENTION_DAYS.days.ago
        current_metadata["clicks"].delete_if do |_, data|
          updated_at = data["updated_at"]
          next false unless updated_at
          Time.parse(updated_at) < cutoff_time
        end

        subscription.metadata = current_metadata
        subscription.save!
        nil
      end
    end

    # Public: Record a dismissal for a specific nudge ID and clean up old records
    #
    # id - Symbol or String representing the unique identifier for the nudge
    # group - Symbol representing the group of the nudge
    # enterprise_id - String representing the enterprise ID (optional)
    # org_id - String representing the organization ID (optional)
    #
    # Returns nothing
    sig do
      params(
        id: T.nilable(T.any(String, Symbol)),
        group: T.nilable(Symbol),
        enterprise_id: T.nilable(T.any(String, Symbol, Integer)),
        org_id: T.nilable(T.any(String, Symbol, Integer))
      ).returns(NilClass)
    end
    def save_a_copy_of_dismissal_analytics_to_dotcom(id: nil, group: nil, enterprise_id: nil, org_id: nil)
      ActiveRecord::Base.connected_to(role: :writing) do
        subscription = find_or_create_in_product_messaging_subscription
        current_metadata = subscription.metadata || {}
        current_metadata["dismissals"] ||= {}

        # Add the new dismissal
        current_metadata["dismissals"][id.to_s] = {
          "updated_at" => Time.current.iso8601
        }

        if group
          current_metadata["dismissals"][id.to_s]["group"] = group.to_s
        end

        if enterprise_id
          current_metadata["dismissals"][id.to_s]["enterprise"] = enterprise_id.to_s
        end

        if org_id
          current_metadata["dismissals"][id.to_s]["org"] = org_id.to_s
        end

        # Remove dismissals older than retention period
        cutoff_time = User::NudgeInteractionDependency::NUDGE_INTERACTION_RETENTION_DAYS.days.ago
        current_metadata["dismissals"].delete_if do |_, data|
          updated_at = data["updated_at"]
          next false unless updated_at
          Time.parse(updated_at) < cutoff_time
        end

        subscription.metadata = current_metadata
        subscription.save!
        nil
      end
    end

    private

    # Find or create the subscription for this user, handling race conditions
    # where two concurrent requests try to create the record simultaneously
    sig { returns(InProductMessagingSubscription) }
    def find_or_create_in_product_messaging_subscription
      user.in_product_messaging_subscription ||
        InProductMessagingSubscription.create!(user: user)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # When another request already created the record; reload and return it.
      T.must(user.reload_in_product_messaging_subscription)
    end
  end
end
