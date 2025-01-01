# typed: true
# frozen_string_literal: true

require "scientist"

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class IssueEvent < Platform::Loader
          include GitHub::Memoizer
          include GitHub::ResilienceMixin
          include IssueTimelineHelper::TotalCountOptimizationHelper

          def self.load(issue_id, repository_id, owner_id, viewer, visible_events_only: false, requested_issue_event_type_names: [], cap_filter: nil, total_count_optimization: false, first: nil, total_count_limit: nil)
            self.for(viewer, visible_events_only, requested_issue_event_type_names, cap_filter, total_count_optimization, first, total_count_limit).load([issue_id, repository_id, owner_id])
          end

          def initialize(viewer, visible_events_only, requested_issue_event_type_names, cap_filter, total_count_optimization, first, total_count_limit)
            @viewer = viewer
            @visible_events_only = visible_events_only
            @requested_issue_event_type_names = requested_issue_event_type_names
            @cap_filter = cap_filter
            @total_count_optimization = total_count_optimization
            @first = first
            @total_count_limit = total_count_limit
          end

          def fetch(issue_repo_and_owner_ids)
            fetch_placeholders(issue_repo_and_owner_ids)
          end

          private

          attr_reader :viewer, :visible_events_only, :requested_issue_event_type_names

          def fetch_placeholders(issue_repo_and_owner_ids)
            issue_ids, repository_ids, owner_ids = issue_repo_and_owner_ids.transpose
            issue_owner_ids = issue_ids.zip(owner_ids).to_h
            repository_ids.uniq!

            requested_event_column_names = requested_issue_event_type_names.map do |type_name|
              ::IssueEvent.platform_type_name_to_column(type_name)
            end

            selected_attributes = [:issue_id, :id, :created_at, :event, :commit_id, :actor_id, :repository_id, :commit_repository_id, :project_id]
            base_scope = ::IssueEvent.unscoped.where(issue_id: issue_ids, repository_id: repository_ids)

            loader = ::IssueEvent::Loader.new(
              viewer,
              base_scope: base_scope,
              selected_attributes: selected_attributes,
              visible_events_only: visible_events_only,
              requested_events: requested_event_column_names,
            )

            number_of_placeholders_to_load = number_of_placeholders_to_load(@total_count_optimization, @first, issue_ids.size, @total_count_limit)
            if number_of_placeholders_to_load.nil?
              # Load all placeholders
              events = loader.load
            else
              # Attempt to load the first number_of_placeholders_to_load placeholders
              events = loader.load_first(number_of_placeholders_to_load)
            end

            results_by_issue_id_repo_id_owner_id = Hash.new { |hash, key| hash[key] = [] }

            Promise.all(events.map do |e|
              async_spammy?(e[:actor_id]).then do |spammy|
                next false if spammy && ::IssueEvent::ALLOWLISTED_SPAMMY_TIMELINE_EVENTS.exclude?(e[:event])

                async_actor_blocked_by_viewer?(e[:actor_id]).then do |blocked|
                  next false if blocked

                  async_actor_blocked_by_owner?(e[:actor_id], issue_owner_ids[e[:issue_id]]).then do |blocked_by_owner|
                    next false if blocked_by_owner

                    async_event_visible?(e).then do |visible|
                      next unless visible

                      results_by_issue_id_repo_id_owner_id[[e[:issue_id], e[:repository_id], issue_owner_ids[e[:issue_id]]]] << map_placeholder(e)
                    end
                  end
                end
              end
            end).sync

            results_by_issue_id_repo_id_owner_id
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

          def async_actor_blocked_by_owner?(actor_id, owner_id)
            if actor_id && owner_id && FeatureFlag.vexi.enabled?(:issue_event_actor_blocked_by_owner_check, viewer, default: false)
              UserBlockedCheck.load(owner_id, actor_id)
            else
              Promise.resolve(false)
            end
          end

          def async_event_visible?(e)
            event_type = e[:event]
            case event_type
            when *::IssueEvent::PROJECT_EVENTS
              ProjectEventVisibleCheck.load(viewer, e[:repository_id], e[:id])
            when "referenced"
              return Promise.resolve(true) unless e[:commit_repository_id]

              RepositoryVisibleCheck.load(viewer, e[:commit_repository_id], resource: "contents", cap_filter: @cap_filter).then do |visible|
                next Promise.resolve(true) if visible

                UnlockedRepositoryCheck.load(viewer, e[:commit_repository_id])
              end
            when *::IssueEvent::CROSS_ISSUE_SUBJECT_EVENTS
              IssueSubjectEventVisibleCheck.load(
                viewer,
                e[:id],
                cap_filter: @cap_filter,
                is_sub_issue_event: ::IssueEvent::SUB_ISSUE_EVENTS.include?(event_type),
                is_issue_dependency_event: ::IssueEvent::ISSUE_DEPENDENCY_EVENTS.include?(event_type)
              )
            when "user_blocked"
              return Promise.resolve(true) unless GitHub.spamminess_check_enabled?
              IssueEventSpammySubjectVisibleCheck.load(viewer: viewer, event_id: e[:id])
            when *::IssueEvent::PROJECT_V2_EVENTS
              with_async_database_error_fallback(
                MemexProjectVisibleCheck.load(viewer, e[:project_id], cap_filter: @cap_filter),
                fallback: false,
              )
            when *::IssueEvent::ISSUE_TYPE_EVENTS
              IssueTypeEventVisibleCheck.load(viewer, e[:id]).then do |visible|
                next Promise.resolve(true) if visible
              end
            else
              Promise.resolve(true)
            end
          end

          def map_placeholder(e)
            ::Timeline::Placeholder::IssueEvent.new(
              id: e[:id],
              sort_datetimes: [e[:created_at]],
              event_name: e[:event],
              commit_oid: e[:commit_id],
            )
          end

          memoize def is_emu_viewer?
            viewer&.is_enterprise_managed?
          end
        end
      end
    end
  end
end
