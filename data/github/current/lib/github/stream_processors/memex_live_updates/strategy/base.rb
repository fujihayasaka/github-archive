# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      module Strategy
        class Base
          include FeatureFlagHelper

          extend ActiveSupport::DescendantsTracker

          def self.topics
            raise NotImplementedError
          end

          def execute_strategy!
            raise NotImplementedError
          end

          def initialize(message)
            @message = message
          end

          def execute!
            unless GitHub.projects_new_enabled?
              return Result.new(error_message: "projects_new_disabled")
            end

            execute_strategy!
          end

          private def emit_socket_message_for_memex_project(memex_project, topic, data = {})
            memex_project.notify_memex_channel(data.merge(type: topic.sub(/\Acp1-iad.ingest./, "")))
          end

          private def with_readonly_database_connection
            ActiveRecord::Base.connected_to(role: :reading) do
              yield
            end
          end

          private def feature_enabled_for_actor?(feature)
            feature_enabled_globally_or_for_user?(feature_name: feature, subject: safe_actor)
          end

          private def safe_actor
            return @safe_actor if defined?(@safe_actor)

            @safe_actor = with_readonly_database_connection do
              (User.find_by(id: @message.actor_id) || User.ghost)
            end
          end
        end
      end
    end
  end
end

# Require these up-front so that ActiveSupport::DescendantsTracker is aware of these subclasses.
require "github/stream_processors/memex_live_updates/strategy/update_projects_referencing_issue"
require "github/stream_processors/memex_live_updates/strategy/update_projects_referencing_issue_metadata"
require "github/stream_processors/memex_live_updates/strategy/update_parent_project"
