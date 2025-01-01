# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ProjectSerializer < BaseSerializer
      def scope
        Project.preload(included_associations)
      end

      def as_json(options = {})
        {
          type:       "project",
          url:        url,
          owner:      owner,
          creator:    creator,
          name:       name,
          body:       body,
          number:     number,
          public:     public?,
          columns:    columns,
          created_at: created_at,
          closed_at:  closed_at,
          updated_at: updated_at,
          deleted_at: deleted_at,
        }
      end

      private

      def included_associations
        [:owner, :creator, columns: { cards: :creator }]
      end

      def project
        model
      end

      def columns
        [].tap do |project_columns|
          project.columns.map do |column|
            project_columns << {
              position: column.position,
              name: column.name,
              color: column.color,
              created_at: time(column.created_at),
              updated_at: time(column.updated_at),
              hidden_at: time(column.hidden_at),
              purpose: column.purpose,
              cards: cards_for_column(column),
              workflows: workflows_for_column(column),
            }
          end
        end
      end

      def cards_for_column(column)
        [].tap do |project_cards|
          column.cards.each do |card|
            project_cards << {
              creator: url_for_model(card.creator),
              content: (url_for_model(card.content) if card.content_id.present?), # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              note: card.note,
              priority: card.priority,
              created_at: time(card.created_at),
              updated_at: time(card.updated_at),
              hidden_at: time(card.hidden_at),
              archived_at: time(card.archived_at),
            }
          end
        end
      end

      def workflows_for_column(column)
        [].tap do |workflows|
          column.project_workflows.each do |workflow|
            workflows << {
              creator: url_for_model(workflow.creator),
              last_updater: url_for_model(workflow.last_updater),
              created_at: time(workflow.created_at),
              updated_at: time(workflow.updated_at),
              trigger_type: workflow.trigger_type,
              actions: actions_for_workflow(workflow),
            }
          end
        end
      end

      def actions_for_workflow(workflow)
        [].tap do |actions|
          workflow.actions.each do |action|
            actions << {
              creator: url_for_model(action.creator),
              last_updater: url_for_model(action.last_updater),
              created_at: time(workflow.created_at),
              updated_at: time(workflow.updated_at)
            }
          end
        end
      end

      def owner
        url_for_model(project.owner)
      end

      def creator
        url_for_model(project.creator)
      end

      def name
        project.name
      end

      def body
        project.body
      end

      def number
        project.number
      end

      def public?
        project.public?
      end

      def closed_at
        time(project.closed_at)
      end

      def created_at
        time(project.created_at)
      end

      def deleted_at
        time(project.deleted_at)
      end
    end
  end
end
