# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Memex
      class Message
        extend Forwardable
        def_delegators :@message, :envelope, :retries, :skip, :success, :timestamp, :value, :offset

        # This uses the v2 event because v1 was not being published in all the
        # scenarios we cared about for Memex
        ISSUE_UPDATE_TOPIC = /github\.v2\.IssueUpdate\Z/

        TITLE_COLUMN_TOPICS = [
          /github\.v1\.IssueClose\Z/,
          /github\.v1\.IssueConvertedToDiscussion\Z/,
          /github\.v1\.IssueReopen\Z/,
          /github\.v1\.PullRequestClose\Z/,
          /github\.v1\.PullRequestReopen\Z/,
          /github\.v1\.PullRequestMerge\Z/,
          /github\.v1\.PullRequestConvertToDraft\Z/,
          /github\.v1\.PullRequestInProgress\Z/,
          /github\.v1\.PullRequestReadyForReview\Z/,
          ISSUE_UPDATE_TOPIC,
        ]

        def self.from_consumer_message(message)
          # For now our schemas are 1:1 with our topics, so we can safely
          # compare this value to the topics we subscribe to below.
          schema = message.schema

          if TITLE_COLUMN_TOPICS.any? { |t| t.match?(schema) }
            TitleMessage.new(message)
          else
            raise NotImplementedError, "Support for #{schema} has not been implemented"
          end
        end

        def initialize(message)
          @message = message
        end

        def ignore?
          !!reason_to_ignore
        end

        def reason_to_ignore
          nil
        end

        def topic
          @message.source_message.topic
        end

        def partition
          @message.source_message.partition
        end

        def repository_id
          fetch(:repository, :id)
        end

        def repository_name
          fetch(:repository, :name)
        end

        def content_id
          pull_request_id || issue_id
        end

        def content_type
          if pull_request_id
            "PullRequest"
          elsif issue_id
            "Issue"
          else
            nil
          end
        end

        def actor_id
          fetch(:actor, :id)
        end

        def actor
          return @actor if defined?(@actor)
          @actor = ActiveRecord::Base.connected_to(role: :reading) do
            User.find_by(id: actor_id) || User.ghost
          end
        end

        def pull_request_id
          fetch(:pull_request, :id)
        end

        def issue_id
          fetch(:issue, :id)
        end

        def feature_enabled_for_actor?(feature_name)
          FeatureFlag.vexi.enabled?(feature_name, dummy_actor, default: false)
        end

        private

        def dummy_actor
          @dummy_actor ||= User.new(id: actor_id)
        end

        def fetch(*path)
          @message.value.dig(*path)
        end
      end
    end
  end
end
