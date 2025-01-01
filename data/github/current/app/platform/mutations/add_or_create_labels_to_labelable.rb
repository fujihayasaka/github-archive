# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddOrCreateLabelsToLabelable < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas
      include Issues::Domain::Provider

      description "Adds labels to a labelable object."

      visibility :internal
      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The id of the labelable object to add labels to.", required: true, loads: Interfaces::Labelable
      argument :labels, [Inputs::AddOrCreateLabelsLabelInput], "The label attributes to add.", required: true

      # This mutation can safely read arguments from replicas
      read_arguments_from_replicas!

      error_fields
      field :labelable_record, Interfaces::Labelable, "The item that was labeled.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, labelable:, **inputs)
        permission.async_repo_and_org_owner(labelable).then do |repo, org|
          permission.access_allowed?(:add_label, repo: repo, resource: labelable, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # This uses replicas to the read the data
      def before_resolve(labelable:, **inputs)
        record = labelable
        issue = record.is_a?(PullRequest) ? record.issue : record

        unless issue
          return {
            error: Errors::Unprocessable.new("Issue not found"),
            labels_to_add: nil,
            repository: nil,
            issue: nil
          }
        end

        unless issue.labelable_by?(actor: context[:viewer])
          return {
            error: Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to add labels in this repository."),
            labels_to_add: nil,
            repository: nil,
            issue: nil
          }
        end

        issue.async_repository.then do |repository|
          if record.is_a?(Issue) && !repository.has_issues?
            next {
              error: Errors::Unprocessable::IssuesDisabled.new,
              labels_to_add: nil,
              repository: nil,
              issue: nil
            }
          end

          context[:permission].authorize_content(:issue, :update, repo: repository)

          label_names = inputs[:labels].map { |l| l[:name] }
          labels_to_add = if GitHub.flipper[:issue_dependency_removal].enabled?
            issues_domain.labels.by_repository_and_names(repository_id: repository.id, names: label_names)
          else
            repository.find_labels_by_name(label_names).to_a
          end
          existing_label_names = labels_to_add.map { |l| l.name.downcase }

          inputs[:labels].each do |label|
            unless existing_label_names.include?(label[:name].downcase)
              new_label = repository.labels.new(name: label[:name], description: label[:description], color: label[:color])
              labels_to_add.push(new_label)
            end
          end

          if @context[:permission].integration_user_request?
            issue.modifying_integration = @context[:integration]
          end

          # Set .actor to the modifying user or Bot if the model expects it, to support attribution in Hydro messages
          # and webhooks
          if issue.respond_to?(:actor=)
            issue.actor = @context[:viewer]
          end

          next {
            labels_to_add: labels_to_add,
            repository: repository,
            issue: issue,
            error: nil,
          }
        end
      end

      # this is executed on the primary DB using the write connection
      def resolve(labels_to_add:, repository:, issue:, error: nil)
        # any error from the preprocessing step will be raised here
        if error.present?
          # these error are Platform::Errors::Base, so we can raise them directly
          raise error # rubocop:disable GitHub/UsePlatformErrors
        end

        if labels_to_add.any?(&:invalid?)
          return {
            labelable_record: nil,
            errors: Platform::UserErrors.mutation_errors_for_models(labels_to_add, path_prefix: %w[input labels]),
          }
        end

        read_from_selected_replicas([ApplicationRecord::Repositories]) do
          labels_to_add = labels_to_add.map do |label|
            if label.new_record?
              begin
                label.save
                label
              rescue ActiveRecord::RecordNotUnique
                # This label already exists on the repository, so we don't need to create it again.
                # This can happen if the label was created between the time we fetched the
                # existing labels and the time we tried to create the new ones. (Race condition)
                repository.labels.find_by_name(label.name)
              end
            else
              label
            end
          end

          issue.add_labels(labels_to_add)

          if issue.valid?
            {
              labelable_record: issue,
              errors: [],
            }
          else
            {
              labelable_record: nil,
              errors: Platform::UserErrors.mutation_errors_for_model(issue),
            }
          end
        end
      end
    end
  end
end
