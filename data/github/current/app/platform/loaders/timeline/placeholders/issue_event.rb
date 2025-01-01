# typed: true
# frozen_string_literal: true
require "scientist"

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class IssueEvent < Platform::Loader
          include GitHub::Memoizer

          def self.load(issue_id, repository_id, viewer, visible_events_only: false, requested_issue_event_type_names: [], cap_filter: nil)
            self.for(viewer, visible_events_only, requested_issue_event_type_names, cap_filter).load([issue_id, repository_id])
          end

          def initialize(viewer, visible_events_only, requested_issue_event_type_names, cap_filter)
            @viewer = viewer
            @visible_events_only = visible_events_only
            @requested_issue_event_type_names = requested_issue_event_type_names
            @cap_filter = cap_filter
          end

          def fetch(issue_and_repo_ids)
            fetch_placeholders(issue_and_repo_ids)
          end

          private

          attr_reader :viewer, :visible_events_only, :requested_issue_event_type_names

          def fetch_placeholders(issue_and_repo_ids)
            issue_ids, repository_ids = issue_and_repo_ids.transpose
            repository_ids.uniq!

            requested_event_column_names = requested_issue_event_type_names.map do |type_name|
              ::IssueEvent.platform_type_name_to_column(type_name)
            end

            selected_attributes = [:issue_id, :id, :created_at, :event, :commit_id, :actor_id, :repository_id, :commit_repository_id, :project_id, :project_status, :project_previous_status]
            base_scope = ::IssueEvent.unscoped.where(issue_id: issue_ids, repository_id: repository_ids)

            events = ::IssueEvent::Loader.new(
              viewer,
              base_scope: base_scope,
              selected_attributes: selected_attributes,
              visible_events_only: visible_events_only,
              requested_events: requested_event_column_names,
            ).load

            results_by_issue_id_repo_id = Hash.new { |hash, key| hash[key] = [] }

            Promise.all(events.map do |e|
              async_spammy?(e[:actor_id]).then do |spammy|
                next false if spammy && ::IssueEvent::ALLOWLISTED_SPAMMY_TIMELINE_EVENTS.exclude?(e[:event])

                async_actor_blocked_by_viewer?(e[:actor_id]).then do |blocked|
                  next false if blocked

                  async_event_visible?(e).then do |visible|
                    next unless visible

                    results_by_issue_id_repo_id[[e[:issue_id], e[:repository_id]]] << map_placeholder(e)
                  end
                end
              end
            end).sync

            results_by_issue_id_repo_id
          end

          def async_spammy?(actor_id)
            async_spammy = if is_emu_viewer?
              # An EMU viewer only has access to other EMU content and spammy checks do not apply to EMUs
              # Short circuit spammy checks on this fact instead of loading each individual actor to check is an EMU
              # Note: this skips removing suspended users - EMUs want to see timeline history for suspended users
              Promise.resolve(false)
            else
              UserSpammyCheck.load(actor_id, viewer)
            end
          end

          def async_actor_blocked_by_viewer?(actor_id)
            if actor_id && viewer
              UserBlockedCheck.load(viewer.id, actor_id)
            else
              Promise.resolve(false)
            end
          end

          def async_event_visible?(e)
            case e[:event]
            when *::IssueEvent::PROJECT_EVENTS
              ProjectEventVisibleCheck.load(viewer, e[:repository_id], e[:id])
            when "referenced"
              return Promise.resolve(true) unless e[:commit_repository_id]

              RepositoryVisibleCheck.load(viewer, e[:commit_repository_id], resource: "contents", cap_filter: @cap_filter).then do |visible|
                next Promise.resolve(true) if visible

                UnlockedRepositoryCheck.load(viewer, e[:commit_repository_id])
              end
            when *::IssueEvent::CROSS_ISSUE_SUBJECT_EVENTS
              IssueSubjectEventVisibleCheck.load(viewer, e[:id], cap_filter: @cap_filter)
            when "user_blocked"
              return Promise.resolve(true) unless GitHub.spamminess_check_enabled?
              IssueEventSpammySubjectVisibleCheck.load(viewer: viewer, event_id: e[:id])
            when *::IssueEvent::PROJECT_V2_EVENTS
              MemexProjectVisibleCheck.load(viewer, e[:project_id], cap_filter: @cap_filter)
            else
              Promise.resolve(true)
            end
          end

          def map_placeholder(e)
            if viewer&.feature_enabled?(:load_issue_project_events_mysql)
              memex_props = {
                id: e[:id],
                issue_id: e[:issue_id],
                created_at: e[:created_at],
                sort_datetimes: [e[:created_at]],
                actor_id: e[:actor_id],
                memex_id: e[:project_id],
                was_automated: false,
              }

              case e[:event]
              when "added_to_project_v2"
                ::Timeline::Placeholder::AddedToMemexProject.new(**memex_props)
              when "converted_from_draft"
                ::Timeline::Placeholder::ConvertedFromDraft.new(**memex_props)
              when "removed_from_project_v2"
                ::Timeline::Placeholder::RemovedFromMemexProject.new(**memex_props)
              when "project_v2_item_status_changed"
                ::Timeline::Placeholder::ProjectItemStatusChanged.new(**memex_props.merge({
                  status: e[:project_status],
                  previous_status: e[:project_previous_status],
                }))
              else
                ::Timeline::Placeholder::IssueEvent.new(
                  id: e[:id],
                  sort_datetimes: [e[:created_at]],
                  event_name: e[:event],
                  commit_oid: e[:commit_id],
                )
              end
            else
              ::Timeline::Placeholder::IssueEvent.new(
                id: e[:id],
                sort_datetimes: [e[:created_at]],
                event_name: e[:event],
                commit_oid: e[:commit_id],
              )
            end
          end

          memoize def is_emu_viewer?
            viewer&.is_enterprise_managed? && viewer&.feature_enabled?(:show_suspended_emu_timeline_events)
          end
        end
      end
    end
  end
end
