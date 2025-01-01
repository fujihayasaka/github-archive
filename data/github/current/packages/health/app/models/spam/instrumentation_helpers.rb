# typed: true
# frozen_string_literal: true

module Spam
  module InstrumentationHelpers
    # Public: Prepares array of tags for Datadog increment.
    #
    # event_name - String
    # payload - Hash
    #
    # Returns an Array.
    def self.staff_action_tags(event_name, payload)
      tags = []

      spam_action = \
        case event_name
        when "staff.mark_as_spammy"
          if payload[:hard_flag]
            "hard_flag"
          else
            "flag"
          end
        when "staff.mark_not_spammy"
          if payload[:whitelist]
            "whitelist"
          else
            "unflag"
          end
        end

      tags << "spam_action:#{spam_action}"
      tags << "analyst:#{payload[:staff_actor]}"
      tags << "origin:#{payload[:origin]}"
      tags << "previously_spammy:true" if payload[:previously_spammy]
      tags << "subject:#{payload[:subject]}" if payload[:subject]
      tags << "spammy_classification:#{payload[:spammy_classification]}" if payload[:spammy_classification]

      tags
    end
  end
end
