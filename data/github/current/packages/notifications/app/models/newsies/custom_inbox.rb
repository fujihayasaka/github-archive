# encoding: utf-8
# typed: false
# frozen_string_literal: true

module Newsies
  class CustomInbox < ApplicationRecord::Domain::Notifications
    include GitHub::Relay::GlobalIdentification
    include GitHub::Validations
    extend GitHub::Encoding
    self.utc_datetime_columns = [:created_at, :updated_at]

    NAME_MAX_LENGTH = 1024.bytes
    QUERY_STRING_MAX_LENGTH = 1024.bytes
    COUNT_LIMIT = 1000

    attr_writer :default_filter
    attr_accessor :default_filter_id

    belongs_to :user, required: true

    validates :name,
      uniqueness: { scope: [:user_id], case_sensitive: true },
      bytesize: { maximum: NAME_MAX_LENGTH },
      unicode: true
    validates :query_string,
      bytesize: { maximum: QUERY_STRING_MAX_LENGTH },
      unicode: true

    validate :under_max_inboxes_limit, on: :create
    force_utf8_encoding :name, :query_string

    MAX_INBOXES_PER_USER = 15

    DEFAULT_FILTERS = [
      { default_filter_id: "assigned", name: "🎯 Assigned", query_string: "reason:assign" },
      { default_filter_id: "participating", name: "💬 Participating", query_string: "reason:participating" },
      { default_filter_id: "mentioned", name: "✋ Mentioned", query_string: "reason:mention" },
      { default_filter_id: "team_mentioned", name: "🙌 Team mentioned", query_string: "reason:team-mention" },
      { default_filter_id: "review", name: "👀 Review requested", query_string: "reason:review-requested" },
    ]

    # Returns ActiveRecord instances of the default inboxes
    def self.default_filters(user_id)
      DEFAULT_FILTERS.map do |params|
        record = self.new(params.merge(user_id: user_id, default_filter: true))
        record.readonly!

        record
      end
    end

    # Manually set the global relay id of a default filter because default filters don't have an ActiveRecord ID.
    def global_id
      return default_filter_id if default_filter?
      super
    end

    def platform_type_name
      "NotificationFilter"
    end

    # Returns false if the record is not a default filter
    def default_filter?
      @default_filter || false
    end

    def readable_by?(viewer)
      user_id.present? && user_id == viewer&.id
    end

    batch_method(:unread_count) do |inboxes|
      users_by_id = User.where(id: inboxes.map(&:user_id).uniq).index_by(&:id)

      inboxes.each_with_object(Hash.new { |h, k| h[k] = 0 }) do |inbox, result|
        user = users_by_id[inbox.user_id]
        next unless user

        parsed_query = Search::Queries::NotificationsQuery.new(query: inbox.query_string, viewer: user)

        # If the query specifically excludes unreads, count will
        # always be 0
        next unless parsed_query.statuses.include?("unread")

        # We cannot currently count starred notifications as we do not
        # know their read/unread state
        next if parsed_query.starred?

        filter_by = {
          statuses: ["inbox_unread"],
        }

        # Queries over a big number of rows can result on a timeout
        # By setting this option we can limit the count to not exceed the time limit
        filter_by[:count_limit] = COUNT_LIMIT

        filter_by[:thread_types] = parsed_query.thread_types if parsed_query.thread_type?
        filter_by[:lists] = parsed_query.repositories if parsed_query.repositories.present?
        filter_by[:reasons] = parsed_query.reasons.map(&:downcase) if parsed_query.reasons.present?
        filter_by[:owners] = parsed_query.owners if parsed_query.qualifier_used?(:org)
        filter_by[:authors] = parsed_query.authors if parsed_query.qualifier_used?(:author)

        result[inbox] = GitHub.newsies.web.count(user, filter_by)
      end
    end

    def async_target_for_conditional_access
      async_user.then(&:async_target_for_conditional_access)
    end

    def target_for_conditional_access
      user.target_for_conditional_access
    end

    private

    def under_max_inboxes_limit
      if self.class.where(user_id: attributes["user_id"]).count >= MAX_INBOXES_PER_USER
        errors.add(:base, "User has reached maximum number of allowed inboxes")
      end
    end
  end
end
