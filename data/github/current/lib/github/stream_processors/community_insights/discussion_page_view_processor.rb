# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module CommunityInsights
      class DiscussionPageViewProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "discussion_page_view_processor"
        DEFAULT_SUBSCRIBE_TO = /analytics\.v0\.PageView\Z/

        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        PAGE_RX = %r{
          \A
          #{Regexp.escape(GitHub.url)}/ # instance protocol and hostname, accurate on GHES
          -?[a-z0-9][a-z0-9\-\_]*/ # owner login, from routes
          (?:\w|\.|\-)+/ # repository name, from routes
          discussions/
          \d+[^/]*/? # discussion number, plus optional, ignored trailing characters and slash
          \z
        }ix

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          return unless message.value[:app] == "github"
          return unless PAGE_RX.match?(message.value[:page])

          repo_id = message.value.dig(:repository_id, :value)
          return unless repo_id

          entry_date = Time.at(message.timestamp).to_date
          count_attr = if message.value.dig(:actor_id, :value).present?
            :discussion_logged_in_page_view_count
          else
            :discussion_anonymous_page_view_count
          end

          with_write { CommunityInsightsDailyCount.increment(repo_id, entry_date, count_attr) }
        end
      end
    end
  end
end
