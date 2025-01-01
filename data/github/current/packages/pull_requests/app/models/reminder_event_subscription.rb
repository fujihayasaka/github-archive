# typed: true
# frozen_string_literal: true

class ReminderEventSubscription < ApplicationRecord::Collab
  include GitHub::Validations
  extend GitHub::Encoding
  force_utf8_encoding :options

  belongs_to :subscriber, polymorphic: true

  enum :event_type, {
    review_request: 1,
    team_review_request: 2,
    review_submission: 3,
    comment: 4,
    comment_reply: 5,
    mention: 6,
    assignment: 7,
    pull_request_opened: 8,
    pull_request_labeled: 9,
    pull_request_merged: 10,
    merge_conflict: 11,
    check_failure: 12,
  }

  EVENT_TYPES_PERMITTING_OPTIONS = [
    :check_failure,
    :pull_request_labeled,
    :team_review_request,
  ]
  OPTIONS_BYTESIZE_LIMIT = 1024

  validates :options, bytesize: { maximum: OPTIONS_BYTESIZE_LIMIT }, allow_blank: true, allow_nil: true

  def options=(value)
    # For some reason when adding the validation through `.validates`
    # the attribute's value is marked as frozen and then `.force_utf8_encoding` fails
    value = value.dup if value.frozen?
    super(value)
  end

  def parsed_options
    options.to_s.split(",").map(&:downcase).map(&:strip)
  end

  def options_includes?(target)
    parsed_options.include?(target.to_s.downcase)
  end
end
