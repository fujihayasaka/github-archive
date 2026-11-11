# typed: true
# frozen_string_literal: true

module Repository::NotificationsDependency
  include Notifyd::NetworkHelper
  extend T::Helpers

  requires_ancestor { Repository }

  # Internal: Remove newsies records for users who no longer have access.
  def correct_watchers
    async_purge_subscribers unless public?
  end

  def async_purge_subscribers(restorable_id: nil)
    if restorable_id
      PurgeSubscribersWithRestorableJob.perform_later(id, restorable_id: restorable_id)
    else
      PurgeSubscribersJob.perform_later(id)
    end
  end

  def subscribed_labels(user)
    return [] if notifyd_client.nil?

    request = Notifyd::Proto::Subscriptions::GetRequest.new(
      user_id: user.id,
      filter_by_custom_fields: [
        Notifyd::Proto::Subscriptions::CustomField.new(name: "repository_id", value: id.to_s),
        Notifyd::Proto::Subscriptions::CustomField.new(name: "subject_type", value: "Issue"),
        Notifyd::Proto::Subscriptions::CustomField.new(name: "label_id"),
      ],
    )

    response = make_network_request_to_notifyd(request.class.name) do
      notifyd_client.subscriptions.get(request)
    end

    return [] if response.nil?

    label_ids = Set.new
    response.data.subscriptions.each do |subscription|
      label_id = subscription.custom_fields.find { |field| field.name == "label_id" }.value.to_i
      label_ids.add(label_id)
    end

    Label.smart_sort(labels.where(id: label_ids.to_a), false)
  end

  def subscribed_label_ids(user)
    subscribed_labels(user).map(&:global_relay_id)
  end

  private

  def notifyd_client
    @notifyd_client ||= Notifyd.client
  end
end
