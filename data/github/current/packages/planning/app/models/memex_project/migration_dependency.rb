# typed: true
# frozen_string_literal: true

class MemexProject
  module MigrationDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    requires_ancestor { MemexProject }

    WRITE_BATCH_SIZE = 20
    def configure_status_field!(status_field_spec)
      return unless status_field_spec
      return if status_field_spec.dig(:settings, :options).blank?

      status_field = with_read { status_column }

      new_settings = status_field.settings
      new_settings["options"] = status_field_spec.dig(:settings, :options).map do |o|
        o["color"] = "GRAY"
        o["description"] = ""
        o.except(:id)
      end
      with_write do
        status_field.update!(settings: new_settings)
      end

      status_field
    end

    def configure_default_view!(view_spec)
      return unless view_spec
      return if view_spec[:layout].blank?
      # read the active record once, or else we will read it in each with_write block below
      default_view = with_read { self.default_view }

      with_write do
        default_view&.update!(layout: "#{view_spec[:layout]}_layout")
      end

      visible_fields = view_spec[:visible_fields] || []
      visible_columns = visible_fields.map { |field| find_column_by_name_or_id(field) }.compact

      with_write do
        visible_columns.each do |column|
          default_view&.make_column_visible!(column)
        end
      end

      default_view
    end

    def configure_permissions!(permissions_spec)
      permissions_spec.each do |permission|
        case permission[:actor_type]
        when "Organization"
          actor = with_read { Organization.find(permission[:actor_id]) }

          with_write do
            Configuration::Entry.throttle do
              if permission[:action] == "none"
                update_organization_wide_role(permission[:action], actor)
              else
                update_organization_wide_role(role_for_permitted_action(permission[:action]).name, actor)
              end
            end
          end
        when "User"
          actor = with_read { User.find(permission[:actor_id]) }

          with_write do
            UserRole.throttle do
              grant_role(actor, role_for_permitted_action(permission[:action]))
            end
          end
        when "Team"
          actor = with_read { Team.find(permission[:actor_id]) }
          with_write do
            UserRole.throttle do
              grant_role(actor, role_for_permitted_action(permission[:action]))
            end
          end
        end
      end
    end

    def populate_items!(actor, items_spec, migration)
      return unless items_spec

      if migration.last_migrated_project_item_id
        last_migrated_index = items_spec.find_index { |item| item[:id] == migration.last_migrated_project_item_id }
        items_spec = items_spec.slice((last_migrated_index + 1)..-1)
      end

      items = build_items!(actor, items_spec)

      items.each_slice(WRITE_BATCH_SIZE) do |batch|
        valid_items = with_read { batch.select(&:valid?) }
        with_write do
          MemexProjectItem.throttle do
            valid_items.each do |item|
              Failbot.push("gh.memex.migration.source_project_card.id": item.source_project_card_id)
              save_with_priority!(item, position: :bottom)
              migration.update(last_migrated_project_item_id: item.source_project_card_id)
            end
          end
        end
      end

      items
    end

    def migrate_workflows!(workflows_spec, actor, field_id_store, field_option_id_store)
      workflows_spec.each_slice(WRITE_BATCH_SIZE) do |batch|
        with_write do

          batch.each do |spec|
            workflow_attributes = spec.slice(:name, :enabled, :trigger_type, :content_types)
            workflow_attributes[:actions_attributes] = spec[:actions].map do |action_spec|
              {
                creator: actor,
                action_type: with_read { MemexProjectWorkflowAction.action_types[action_spec[:type].to_sym] },
                arguments: {
                  fieldId: field_id_store.dig(action_spec[:arguments][:field_id]),
                  fieldOptionId: field_option_id_store.dig(
                    action_spec[:arguments][:field_id],
                    action_spec[:arguments][:field_option_id]
                  ),
                }
              }
            end
            MemexProjectWorkflow.throttle do
              workflow = MemexProjectWorkflow.build(memex_project: self, creator: actor, **workflow_attributes)
              workflow.is_migrating = true
              workflow.save!
            end
          end
        end
      end
    end

    private

    def role_for_permitted_action(action)
      role_name = case action
      when "read"
        "project_reader"
      when "write"
        "project_writer"
      when "admin"
        "project_admin"
      end

      with_read { Role.internal_role_by_name(role_name) }
    end

    def construct_draft_issue_content(draft_content)
      return unless draft_content
      first_new_line = draft_content.index("\n")

      if first_new_line.nil?
        return {
          title: draft_content,
          body: nil
        }
      end

      {
        title: draft_content.slice(0, first_new_line),
        body: draft_content
      }
    end

    def lookup_content_from_hash(content_type, content_id, issues_by_id, pulls_by_id)
      return unless content_id && content_type

      return issues_by_id[content_id] if content_type == "Issue"
      pulls_by_id[content_id] if content_type == "PullRequest"
    end

    def prefill_repo_and_collect_archived_ids(collection, archived_repo_ids)
      collection.in_groups_of(1000, false) do |batch|
        # Prefill the repository and user associations because it's accessed at a later point in the migration
        GitHub::PrefillAssociations.prefill_associations(batch, :repository)
        GitHub::PrefillAssociations.prefill_associations(batch, :user)
        repos = batch.map(&:repository)

        # Batch load to avoid N+1 queries from Repository#archived?
        archived_results = Promise.all(repos.map(&:async_archived?)).sync
        repos.each.with_index do |repo, i|
          if archived_results[i]
            archived_repo_ids << repo.id
          end
        end
      end
    end

    def build_items!(actor, items_spec)
      status_field = with_read { status_column }
      items = []
      issue_items, pull_items = items_spec.partition { |s| s[:content_type] == "Issue" }
      issues_by_id = with_read { Issue.where(id: issue_items.map { |i| i[:content_id] }).index_by(&:id) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      pulls_by_id = with_read { PullRequest.where(id: pull_items.map { |i| i[:content_id] }).index_by(&:id) }

      archived_repo_ids = Set.new
      prefill_repo_and_collect_archived_ids(issues_by_id.values, archived_repo_ids)
      prefill_repo_and_collect_archived_ids(pulls_by_id.values, archived_repo_ids)

      # Prefill the issue association for pull requests, as we will use this for building denormalized column data later
      GitHub::PrefillAssociations.prefill_associations(pulls_by_id.values, :issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      items_spec.each do |source_item|
        item_status = source_item[:column_values].find { |column_value| column_value[:name] == "Status" }
        matching_status = status_field.settings["options"].find { |option| option["name"] == item_status[:value].strip }

        unless matching_status
          raise "Unable to find matching status for column name, abandoning migration..."
        end

        status_id = matching_status["id"]

        content = lookup_content_from_hash(source_item[:content_type], source_item[:content_id], issues_by_id, pulls_by_id)
        draft_content = construct_draft_issue_content(source_item[:draft_content])

        item = build_item(
          creator: actor,
          draft_issue_title: draft_content ? draft_content[:title] : nil,
          draft_issue_body: draft_content ? draft_content[:body] : nil,
          issue_or_pull: content,
          column_data:  {
            column: status_field,
            value: status_id,
            json_value: { raw: status_id, html: status_id }
          },
          skip_draft_issue_reference: true
        )

        unless item.nil?
          is_card_repo_archived = content&.repository_id && archived_repo_ids.include?(content.repository_id)

          item.mark_as_archived if source_item[:is_archived] || is_card_repo_archived
          item.source_project_card_id = source_item[:id]
          items.push(item)
        end
      end

      discard_overflow_items!(items)
    end

    def discard_overflow_items!(items)
      if items.length <= MemexProjectItem::ITEM_LIMIT
        return items
      end

      # If there are more items than the limit, we aim to keep as many unarchived items
      # as possible. If space allows, we include as many archived items as we can.
      #
      # This is a simplified version of the logic used previously, when archived items
      # and unarchived items had different limits:
      # https://github.com/github/memex/issues/11485#issuecomment-1230701327
      source_archived, source_unarchived = items.partition(&:archived?)

      space_for_archived_items = MemexProjectItem::ITEM_LIMIT - source_unarchived.length

      if space_for_archived_items <= 0
        # If there is no space for archived items, we discard archived items and return unarchived items up to the limit
        return source_unarchived.slice(0, MemexProjectItem::ITEM_LIMIT) # rubocop:disable Style/RedundantReturn
      elsif space_for_archived_items > 0
        # If there is space for archived items, we include as many as we can up to the limit
        return source_unarchived + source_archived.slice(0, space_for_archived_items) # rubocop:disable Style/RedundantReturn
      end
    end

    # Simple wrapper for connecting to read pool for read operations only.
    def with_read
      ActiveRecord::Base.connected_to(role: :reading) do
        yield
      end
    end

    # Simple wrapper for connecting to write for write operations only.
    def with_write
      ActiveRecord::Base.connected_to(role: :writing) do
        yield
      end
    end
  end
end
