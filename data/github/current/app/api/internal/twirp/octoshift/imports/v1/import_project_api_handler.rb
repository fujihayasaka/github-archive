# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      class ImportProjectAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Helpers::ModelDelay
        include Helpers::Attribution

        PURPOSE_MAP = {
          COLUMN_PURPOSE_INVALID: nil,
          COLUMN_PURPOSE_TODO: "todo",
          COLUMN_PURPOSE_IN_PROGRESS: "in_progress",
          COLUMN_PURPOSE_DONE: "done",
        }.freeze

        CONTENT_TYPE = {
          CONTENT_TYPE_INVALID: nil,
          CONTENT_TYPE_ISSUE: "Issue",
          CONTENT_TYPE_NOTE: "Note"
        }.freeze

        TRIGGER_TYPE = {
          TRIGGER_TYPE_INVALID: nil,
          TRIGGER_TYPE_ISSUE_PENDING_CARD_ADDED_TRIGGER: "issue_pending_card_added",
          TRIGGER_TYPE_ISSUE_CLOSED_TRIGGER: "issue_closed",
          TRIGGER_TYPE_ISSUE_REOPENED_TRIGGER: "issue_reopened",
          TRIGGER_TYPE_PR_APPROVED_TRIGGER: "pr_approved",
          TRIGGER_TYPE_PR_CLOSED_NOT_MERGED_TRIGGER: "pr_closed_not_merged",
          TRIGGER_TYPE_PR_MERGED_TRIGGER: "pr_merged",
          TRIGGER_TYPE_PR_PENDING_APPROVAL_TRIGGER: "pr_pending_approval",
          TRIGGER_TYPE_PR_PENDING_CARD_ADDED_TRIGGER: "pr_pending_card_added",
          TRIGGER_TYPE_PR_REOPENED_TRIGGER: "pr_reopened",
          TRIGGER_TYPE_REVIEW_DISMISSED_TRIGGER: "review_dismissed",
        }.freeze

        USER_MAP_FIELDS = %i[id spammy login].freeze
        ISSUE_MAP_FIELDS = %i[id pull_request_id user_hidden user_id number].freeze

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportProjectAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        # Public: Implementation of the ImportProject Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportProjectRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportProjectResponse, or a Twirp::Error.
        def import_project(req, env)
          check_model_replication_delay!(ImportableProject)

          @req = req
          @errors = []

          if req.name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name")
          end
          if req.number.negative? || req.number.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "number")
          end
          if req.owner_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_login")
          end
          if req.owner_type.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_type")
          end
          if req.creator_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "creator_login")
          end
          if req.created_at.nil?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end

          case req.owner_type
          when :OWNER_TYPE_REPOSITORY
            owner = replica(Repository).find_by(id: req.repository_id)
            unless owner && owner.active?
              return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
            end
          when :OWNER_TYPE_USER
            owner = find_mannequin_or_user_by_login(req.owner_login)
            unless owner
              return Twirp::Error.not_found("User not found.", argument: "owner_login", value: req.owner_login)
            end
          when :OWNER_TYPE_ORGANIZATION
            owner = replica(Organization).find_by(login: req.owner_login)
            unless owner
              return Twirp::Error.not_found("Organization not found.", argument: "owner_login", value: req.owner_login)
            end
          else
            return Twirp::Error.invalid_argument("must be Repository, User, or Organization", argument: "owner_type")
          end

          user = find_mannequin_or_user_by_login(req.creator_login)
          unless user
            return Twirp::Error.not_found("User not found.", argument: "creator_login", value: req.creator_login)
          end

          # Querying on `name`, `owner_id`, and `owner_type` compound index.
          project_exists = replica(Project).query do |klass|
            klass.where(name: req.name, owner_id: owner.id, owner_type: owner.class.name, number: req.number).exists?
          end

          return already_exists_error_handler("Project") if project_exists

          importable_project = ImportableProject.new(
            owner: owner,
            creator: user,
            name: req.name,
            body: req.body,
            number: req.number,
            public: req.is_public,
            created_at: req.created_at&.to_time,
            updated_at: req.updated_at&.to_time,
            closed_at: req.closed_at&.to_time
          )

          ActiveRecord::Base.connected_to(role: :writing) do
            ImportableProject.transaction do
              rate_limited_mode(importable_project) { importable_project.save }

              import_columns(importable_project, req.columns)
            end
          end

          return save_model_error_handler(importable_project) unless importable_project.persisted?

          # Adding columns touches the project model, so at the very end, update the updated_at
          # attribute so that it reflects the actual request value.
          unless req.updated_at.nil?
            ActiveRecord::Base.connected_to(role: :writing) do
              importable_project.touch(time: req.updated_at.to_time)
            end
          end

          {
            project: {
              id: importable_project.id
            },
            project_import_errors: errors
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the ImportProjectColumn Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportProjectColumnRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportProjectColumnResponse, or a Twirp::Error.
        def import_project_column(req, env)
          check_model_replication_delay!(ImportableProjectColumn)

          @req = req
          @errors = []

          if req.name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name")
          end

          if req.created_at.nil?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end

          project = replica(Project).find_by(id: req.imported_project_id)

          unless project
            return Twirp::Error.not_found("Project not found.", argument: "imported_project_id", value: req.imported_project_id.to_s)
          end

          importable_column = ImportableProjectColumn.new(
            project_id: project.id,
            name: req.name,
            color: req.color,
            created_at: req.created_at&.to_time,
            updated_at: req.updated_at&.to_time,
            purpose: PURPOSE_MAP[req.purpose],
            position: req.position,
            hidden_at: req.hidden_at&.to_time
          )

          ActiveRecord::Base.connected_to(role: :writing) do
            ImportableProjectColumn.transaction do
              Project.no_touching do
                rate_limited_mode(importable_column) { importable_column.save }

                raise ActiveRecord::Rollback unless importable_column.persisted?

                import_workflows(importable_column, req.workflows)

                importable_column.touch(time: req.updated_at.to_time) unless req.updated_at.nil?
              end
            end
          end

          return save_model_error_handler(importable_column) unless importable_column.persisted?

          {
            imported_project_column_id: importable_column.id,
            project_column_import_errors: errors
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the ImportProjectCards Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportProjectCardsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportProjectCardsResponse, or a Twirp::Error.
        def import_project_cards(req, env)
          check_model_replication_delay!(ImportableProjectCard)

          @req = req
          @errors = []

          project_column = replica(ProjectColumn).find_by(id: req.imported_project_column_id)

          unless project_column
            return Twirp::Error.not_found("Project column not found.", argument: "imported_project_column_id", value: req.imported_project_column_id.to_s)
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            ImportableProjectCard.transaction do
              ProjectColumn.no_touching do
                import_cards(project_column, req.project_cards)
              end
            end
          end

          { project_card_import_errors: errors }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        attr_reader :req
        attr_accessor :errors

        def import_columns(project, columns)
          columns.each do |column|
            if column.name.empty?
              errors << build_column_error_hash(column, "Project Column name must be non-empty")
              next
            end

            if column.created_at.nil?
              errors << build_column_error_hash(column, "created_at must be non-empty")
              next
            end

            importable_column = ImportableProjectColumn.new(
              project: project,
              name: column.name,
              color: column.color,
              created_at: column.created_at&.to_time,
              updated_at: column.updated_at&.to_time,
              purpose: PURPOSE_MAP[column.purpose],
              position: column.position,
              hidden_at: column.hidden_at&.to_time
            )

            rate_limited_mode(importable_column) do
              unless importable_column.save
                validation_message = importable_column.errors.full_messages.join(", ")
                errors << build_column_error_hash(column, validation_message)
                next
              end
            end

            import_cards(importable_column, column.cards) unless column.cards.empty?
            import_workflows(importable_column, column.workflows) unless column.workflows.empty?

            unless column.updated_at.nil?
              importable_column.touch(time: column.updated_at.to_time)
            end
          end
        end

        def import_cards(project_column, cards)
          project = project_column.project

          card_content_ids = cards.map(&:content_id)

          issue_map = replica(Issue).query do |klass|
            klass.where(repository: project.owner, number: card_content_ids).select(*ISSUE_MAP_FIELDS).to_h { |issue| [issue.number, issue] }
          end

          card_user_map = build_user_map(cards, :creator_login, USER_MAP_FIELDS)

          cards.each do |card|
            if card.creator_login.empty?
              errors << build_card_error_hash(card, project_column, "creator_login must be non-empty")
              next
            end

            if card.created_at.nil?
              errors << build_card_error_hash(card, project_column, "created_at must be non-empty")
              next
            end

            case card.content_type
            when :CONTENT_TYPE_INVALID
              errors << build_card_error_hash(card, project_column, "content_type must be valid")
              next
            when :CONTENT_TYPE_ISSUE
              if card.content_id.zero? || card.content_id.negative?
                errors << build_card_error_hash(card, project_column, "content_id must be valid")
                next
              end

              issue = issue_map[card.content_id]
              unless issue
                if project.owner_type != "Repository"
                  errors << build_card_error_hash(card, project_column, "project owner must be a repository")
                else
                  errors << build_card_error_hash(card, project_column, "issue with number: #{card.content_id} could not be found")
                end
                next
              end
            when :CONTENT_TYPE_NOTE
              if card.note.empty?
                errors << build_card_error_hash(card, project_column, "note must be non-empty")
                next
              end
            end

            card_user = card_user_map[card.creator_login]
            unless card_user
              errors << build_card_error_hash(card, project_column, "user with login: #{card.creator_login} not found")
              next
            end

            importable_card = ImportableProjectCard.new(
              project_id: project.id,
              column_id: project_column.id,
              creator: card_user,
              content_type: CONTENT_TYPE[card.content_type],
              content: (issue if card.content_type == :CONTENT_TYPE_ISSUE),
              note: (card.note if card.content_type == :CONTENT_TYPE_NOTE),
              priority: card_priority(card),
              created_at: card.created_at&.to_time,
              updated_at: card.updated_at&.to_time,
              archived_at: card.archived_at&.to_time,
              hidden_at: card.hidden_at&.to_time
            )

            unless importable_card.save
              validation_message = importable_card.errors.full_messages.join(", ")
              errors << build_card_error_hash(card, project_column, validation_message)
              next
            end
          rescue ActiveRecord::RecordNotUnique
            validation_message = "ProjectColumn already has a Card with priority #{card.priority}"
            errors << build_card_error_hash(card, project_column, validation_message)
            next
          end
        end

        def import_workflows(project_column, workflows)
          workflow_creator_map = build_user_map(workflows, :creator_login, USER_MAP_FIELDS)
          workflow_last_updater_map = build_user_map(workflows, :last_updater_login, USER_MAP_FIELDS)

          workflows.each do |workflow|
            trigger_type = workflow.trigger_type

            if workflow.creator_login.empty?
              errors << build_workflow_error_hash(trigger_type, project_column, "creator_login must be non-empty")
              next
            end

            if workflow.created_at.nil?
              errors << build_workflow_error_hash(trigger_type, project_column, "created_at must be non-empty")
              next
            end

            if workflow.trigger_type == :TRIGGER_TYPE_INVALID
              errors << build_workflow_error_hash(trigger_type, project_column, "trigger_type must be valid")
              next
            end

            creator = workflow_creator_map[workflow.creator_login]
            unless creator
              errors << build_workflow_error_hash(trigger_type, project_column, "user with login: #{workflow.creator_login} not found")
              next
            end

            if workflow.last_updater_login.present?
              last_updater = workflow_last_updater_map[workflow.last_updater_login]

              unless last_updater
                errors << build_workflow_error_hash(trigger_type, project_column, "user with login: #{workflow.last_updater_login} not found")
                next
              end
            end

            project_workflow = ProjectWorkflow.new(
              project_id: project_column.project.id,
              project_column_id: project_column.id,
              creator: creator,
              last_updater: last_updater,
              trigger_type: TRIGGER_TYPE[workflow.trigger_type],
              created_at: workflow.created_at&.to_time,
              updated_at: workflow.updated_at&.to_time
            )

            unless project_workflow.save
              validation_message = project_workflow.errors.full_messages.join(", ")
              errors << build_workflow_error_hash(trigger_type, project_column, validation_message)
              next
            end

            import_workflow_actions(project_workflow, workflow.actions, workflow.trigger_type) if workflow.actions.any?

            unless workflow.updated_at.nil?
              project_workflow.touch(time: workflow.updated_at.to_time)
            end
          end
        end

        def import_workflow_actions(project_workflow, actions, trigger_type)
          action_creator_map = build_user_map(actions, :creator_login, USER_MAP_FIELDS)
          action_last_updater_map = build_user_map(actions, :last_updater_login, USER_MAP_FIELDS)

          actions.each do |action|
            if action.creator_login.empty?
              errors << build_workflow_action_error_hash(trigger_type, project_workflow, "creator_login must be non-empty")
              next
            end

            if action.created_at.nil?
              errors << build_workflow_action_error_hash(trigger_type, project_workflow, "created_at must be non-empty")
              next
            end

            creator = action_creator_map[action.creator_login]
            unless creator
              errors << build_workflow_action_error_hash(trigger_type, project_workflow, "user with login: #{action.creator_login} not found")
              next
            end

            if action.last_updater_login.present?
              last_updater = action_last_updater_map[action.last_updater_login]
              unless last_updater
                errors << build_workflow_action_error_hash(trigger_type, project_workflow, "user with login: #{action.last_updater_login} not found")
                next
              end
            end

            project_workflow_action = ProjectWorkflowAction.new(
              project_id: project_workflow.project_id,
              project_workflow_id: project_workflow.id,
              creator: creator,
              last_updater: last_updater,
              action_type: ProjectWorkflowAction::TRANSITION_TO_COLUMN,
              created_at: action.created_at&.to_time,
              updated_at: action.updated_at&.to_time
            )

            unless project_workflow_action.save
              validation_message = project_workflow_action.errors.full_messages.join(", ")
              errors << build_workflow_action_error_hash(trigger_type, project_workflow, validation_message)
              next
            end
          end
        end

        def identify_card(project_card)
          case project_card.content_type
          when :CONTENT_TYPE_NOTE
            "'#{project_card.note[0..20]}'"
          when :CONTENT_TYPE_ISSUE
            project_card.content_id
          else
            project_card.note.present? ? "'#{project_card.note[0..20]}'" : project_card.content_id
          end
        end

        def card_priority(project_card)
          return nil if project_card.has_nil_priority
          project_card.priority
        end

        def build_card_error_hash(project_card, project_column, message)
          error_message = "Project Card: #{identify_card(project_card)} in Project Column: '#{project_column.name}' could not be imported. error_message: #{message}"
          build_error_hash(:PROJECT_MODEL_TYPE_PROJECT_CARD, error_message)
        end

        def build_column_error_hash(project_column, message)
          error_message = "Project Column: '#{project_column.name}' could not be imported. error_message: #{message}"
          build_error_hash(:PROJECT_MODEL_TYPE_PROJECT_COLUMN, error_message)
        end

        def build_workflow_error_hash(trigger_type, project_column, message)
          error_message = "Project Workflow: '#{trigger_type}' in Project Column: '#{project_column.name}' could not be imported. error_message: #{message}"
          build_error_hash(:PROJECT_MODEL_TYPE_PROJECT_WORKFLOW, error_message)
        end

        def build_workflow_action_error_hash(trigger_type, project_workflow, message)
          error_message = "Project Workflow Action: '#{trigger_type}' in Project Column: '#{project_workflow.project_column.name}' could not be imported. error_message: #{message}"
          build_error_hash(:PROJECT_MODEL_TYPE_PROJECT_WORKFLOW_ACTION, error_message)
        end

        def build_error_hash(type, message)
          {
            error_message: message,
            model_type: type
          }
        end
      end
    end
  end
end
