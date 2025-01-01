# typed: true
# frozen_string_literal: true

module Notifyd
  class LabelSubscription
    include Notifyd::Subscription

    attr_reader :user, :thread, :notifyd_subscriptions

    def initialize(user, notifyd_subscriptions = [])
      @user = user
      @notifyd_subscriptions = notifyd_subscriptions
    end

    #    [{
    #      reason: "subscribed",
    #      custom_fields: [
    #        { name: "repository_id", value: "123" },
    #        { name: "label_id", value: "1" },
    #        { name: "label_name", value: "bug" },
    #        { name: "owner_id", value: "456" },
    #        { name: "subject_type", value: "Issue" },
    #      ]
    #    },
    #    {
    #      reason: "subscribed",
    #      custom_fields: [
    #        { name: "repository_id", value: repo.id.to_s },
    #        { name: "label_id", value: label_id.to_s },
    #        { name: "label_name", value: repo.labels.find(label_id).name },
    #        { name: "owner_id", value: repo.owner.id.to_s },
    #        { name: "subject_type", value: "Issue" },
    #      ]
    #   }]
    def valid?
      # Label subscription in Notifyd consists of 2 subscribtions:
      #   1. for the issue events create and comment
      #   2. for the label events labeled and unlabeled
      return false unless notifyd_subscriptions.length == 2
      return false unless validate_reason(notifyd_subscriptions[0].reason)
      return false unless validate_reason(notifyd_subscriptions[1].reason)
      return false unless validate_custom_fields(notifyd_subscriptions[0].custom_fields)
      return false unless validate_custom_fields(notifyd_subscriptions[1].custom_fields)
      return false unless custom_field_present(notifyd_subscriptions[0].custom_fields, "label_id").value == custom_field_present(notifyd_subscriptions[1].custom_fields, "label_id").value
      true
    end

    def ignored?
      # we do not ignore labels yet
      false
    end

    def subscribed?
      valid? && !ignored?
    end

    def reason
      "subscribed"
    end

    def events_only?
      false
    end

    def list
      nil
    end

    private

    def validate_custom_fields(custom_fields)
      return false unless custom_field_present(custom_fields, "repository_id")
      return false unless custom_field_present(custom_fields, "label_id")
      return false unless custom_field_present(custom_fields, "label_name")
      return false unless custom_field_present(custom_fields, "owner_id")
      return false unless custom_field_present(custom_fields, "subject_type")
      true
    end

    def custom_field_present(custom_fields, name)
      custom_fields.find { |field| field.name == name }
    end

    def validate_reason(reason)
      reason == "subscribed"
    end
  end
end
