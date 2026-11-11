# typed: strict
# frozen_string_literal: true

module User::NudgeInteractionDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ::User }

  # Number of days to keep nudge interaction records before cleanup
  # This used to be 29 days to abide by GDPR but because we have
  # > has_one :in_product_messaging_subscription, dependent: :destroy
  # We no longer need to have that limit since records will be cleaned up
  # with user data
  NUDGE_INTERACTION_RETENTION_DAYS = 180

  # Public: Check if the user is subscribed to in-product messages
  #
  # Returns boolean
  sig { returns(T::Boolean) }
  def subscribed_to_in_product_messages?
    # This only returns false if a user is explicitly unsubscribed
    # and intentionally returns true if a users preference is nil
    # meaning they have never opted out
    return false if in_product_messaging_subscription&.subscribed? == false
    true
  end

  # Public: Check if user has clicked a nudge relative to a specified time
  #
  # id     - String or Symbol representing the nudge ID (default: nil)
  # before - ActiveSupport::Duration time period to check before now (default: nil)
  # after  - ActiveSupport::Duration time period to check after now (default: nil)
  # on     - Date or Time to check for interactions occurring on that day (default: nil)
  # group  - Symbol specifying the group nudge (default: nil)
  # type   - Symbol specifying the type of interaction (:impression, :click, :dismissal) (default: nil)
  # excluded_ids - Array of Strings or Symbols representing nudge IDs to exclude from the check (default: [])
  # all_ids - Array of Strings or Symbols where all IDs must have been interacted with (default: nil)
  # any_ids - Array of Strings or Symbols where at least one ID must have been interacted with (default: nil)
  # enterprise_id - String representing the enterprise ID (optional)
  # org_id - String representing the organization ID (optional)
  #
  # Examples:
  #   interacted_with_a_nudge(before: 2.days) # checks if interaction was within last 2 days
  #   interacted_with_a_nudge(after: 1.week)  # checks if interaction was more than 1 week ago
  #   interacted_with_a_nudge(on: Date.today)  # checks if interaction occurred today
  #   interacted_with_a_nudge(group: :connect, excluded_ids: [:hello_world]) # checks group but excludes specific ID
  #   interacted_with_a_nudge(all_ids: [:nudge1, :nudge2], before: 1.day) # checks if ALL nudges were interacted with
  #   interacted_with_a_nudge(any_ids: [:nudge1, :nudge2], before: 1.day) # checks if ANY nudge was interacted with
  #
  # Returns Boolean indicating if user interacted with a nudge within the specified time criteria
  sig do
    params(
      id: T.nilable(T.any(String, Symbol)),
      before: T.nilable(Time),
      after: T.nilable(Time),
      on: T.nilable(T.any(Date, Time, String)),
      group: T.nilable(Symbol),
      type: T.nilable(Symbol),
      excluded_ids: T::Array[T.any(String, Symbol)],
      all_ids: T.nilable(T::Array[T.any(String, Symbol)]),
      any_ids: T.nilable(T::Array[T.any(String, Symbol)]),
      enterprise_id: T.nilable(T.any(String, Symbol, Integer)),
      org_id: T.nilable(T.any(String, Symbol, Integer))
    ).returns(T::Boolean)
  end
  def interacted_with_a_nudge(id: nil, before: nil, after: nil, on: nil, group: nil, type: nil, excluded_ids: [], all_ids: nil, any_ids: nil, enterprise_id: nil, org_id: nil)
    # Validate time parameters
    time_params = [before, after, on].compact
    Kernel.raise ArgumentError, "Must provide either before:, after:, or on: parameter" if time_params.empty?
    Kernel.raise ArgumentError, "Can only provide one of before:, after:, or on: parameters" if time_params.length > 1

    # Validate ID parameters - ensure only one ID-related parameter is provided
    id_params = [id, group, all_ids, any_ids].compact
    Kernel.raise ArgumentError, "Must provide one of id:, group:, all_ids:, or any_ids: parameter" if id_params.empty?
    Kernel.raise ArgumentError, "Can only provide one of id:, group:, all_ids:, or any_ids: parameters" if id_params.length > 1

    namespace_params = [enterprise_id, org_id].compact
    Kernel.raise ArgumentError, "Can only provide one of enterprise_id: or org_id: parameters" if namespace_params.length > 1

    subscription = in_product_messaging_subscription
    return false unless subscription
    return false unless subscription.metadata

    type_key =
      case type
      when :impression then "impressions"
      when :click then "clicks"
      when :dismissal then "dismissals"
      else return false
      end

    return false unless subscription.metadata[type_key]

    if group
      # Convert excluded_ids to strings for comparison
      excluded_ids = Kernel.Array(excluded_ids).map(&:to_s)

      # Search through all entries in the interaction type for matching group
      # excluding any IDs that are in the excluded_ids list
      matching_interactions = subscription.metadata[type_key].reject do |key, _|
        excluded_ids.include?(key)
      end.find do |_, data|
        data["group"]&.to_sym == group.to_sym
      end

      return false unless matching_interactions
      interaction_data = matching_interactions[1] # [1] gets the value from the key-value pair
      check_interaction_time(interaction_data, before, after, on, enterprise_id: enterprise_id, org_id: org_id)
    elsif all_ids || any_ids
      ids_to_check = T.must(all_ids || any_ids).map(&:to_s)
      results = ids_to_check.map do |check_id|
        interaction_data = T.let(subscription.metadata[type_key][check_id], T.untyped)
        next false unless interaction_data
        check_interaction_time(interaction_data, before, after, on, enterprise_id: enterprise_id, org_id: org_id)
      end

      all_ids ? results.all? : results.any?
    else
      # If not searching by group or multiple IDs, then search by the single ID
      interaction_data = subscription.metadata[type_key][id.to_s]
      check_interaction_time(interaction_data, before, after, on, enterprise_id: enterprise_id, org_id: org_id)
    end
  end

  # Helper method to check if an interaction occurred within the specified time criteria
  sig do
    params(
      interaction_data: T.nilable(T::Hash[String, T.untyped]),
      before: T.nilable(Time),
      after: T.nilable(Time),
      on: T.nilable(T.any(Date, Time, String)),
      enterprise_id: T.nilable(T.any(String, Symbol, Integer)),
      org_id: T.nilable(T.any(String, Symbol, Integer))
    ).returns(T::Boolean)
  end
  def check_interaction_time(interaction_data, before, after, on, enterprise_id: nil, org_id: nil)
    namespace_params = [enterprise_id, org_id].compact
    Kernel.raise ArgumentError, "Can only provide one of enterprise_id: or org_id: parameters" if namespace_params.length > 1

    return false unless interaction_data && interaction_data["updated_at"]

    interaction_time = Time.parse(interaction_data["updated_at"])

    return false if enterprise_id && interaction_data["enterprise"] != enterprise_id.to_s

    return false if org_id && interaction_data["org"] != org_id.to_s

    if on
      # Convert both times to dates for comparison if checking on a specific day
      on_date = on.respond_to?(:to_date) ? on.to_date : Date.parse(on.to_s)
      interaction_date = interaction_time.to_date
      return interaction_date == on_date
    else
      return false if before && interaction_time > before
      return false if after && interaction_time < after
    end

    true
  end

  # Public: Check if a nudge has exceeded the maximum number of impressions
  # and automatically dismiss it if so
  #
  # impressions - Integer maximum number of impressions allowed
  # id - Symbol or String representing the unique identifier for the nudge
  # enterprise_id - String representing the enterprise ID (optional)
  # org_id - String representing the organization ID (optional)
  #
  # Returns Boolean indicating if impressions were exceeded
  sig do
    params(
      impressions: Integer,
      id: T.any(String, Symbol),
      enterprise_id: T.nilable(T.any(String, Symbol, Integer)),
      org_id: T.nilable(T.any(String, Symbol, Integer))
    ).returns(T::Boolean)
  end
  def nudge_exceeds(impressions:, id:, enterprise_id: nil, org_id: nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      subscription = in_product_messaging_subscription
      nudge_id = id.to_s
      return false unless subscription

      current_metadata = subscription.metadata || {}
      current_metadata["impressions"] ||= {}
      current_metadata["impressions"][nudge_id] ||= {
        "count" => 0,
        "updated_at" => nil
      }

      if enterprise_id && current_metadata["impressions"][nudge_id]["enterprise"] != enterprise_id.to_s
        # no match
        return false
      end

      if org_id && current_metadata["impressions"][nudge_id]["org"] != org_id.to_s
        # no match
        return false
      end

      if current_metadata["impressions"][nudge_id]["count"] >= impressions
        dismiss_notice(nudge_id)
        true
      else
        false
      end
    end
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
  def track_nudge_impression(id: nil, group: nil, enterprise_id: nil, org_id: nil)
    namespace_params = [enterprise_id, org_id].compact
    Kernel.raise ArgumentError, "Can only provide one of enterprise_id: or org_id: parameters" if namespace_params.length > 1

    ActiveRecord::Base.connected_to(role: :writing) do
      subscription = find_or_create_in_product_messaging_subscription

      current_metadata = subscription.metadata || {}
      current_metadata["impressions"] ||= {}

      # Clean up old impressions
      cutoff_time = NUDGE_INTERACTION_RETENTION_DAYS.days.ago
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
  def track_nudge_click(id: nil, group: nil, enterprise_id: nil, org_id: nil)
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
      cutoff_time = NUDGE_INTERACTION_RETENTION_DAYS.days.ago
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

  sig do
    params(
      id: T.nilable(T.any(String, Symbol)),
      group: T.nilable(Symbol),
      enterprise_id: T.nilable(T.any(String, Symbol, Integer)),
      org_id: T.nilable(T.any(String, Symbol, Integer))
    ).returns(NilClass)
  end
  def track_nudge_dismissal(id: nil, group: nil, enterprise_id: nil, org_id: nil)
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
      cutoff_time = NUDGE_INTERACTION_RETENTION_DAYS.days.ago
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
    in_product_messaging_subscription ||
      InProductMessagingSubscription.create!(user: self)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # When another request already created the record; reload and return it.
    T.must(reload_in_product_messaging_subscription)
  end
end
