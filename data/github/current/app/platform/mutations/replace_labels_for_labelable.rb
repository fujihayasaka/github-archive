# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReplaceLabelsForLabelable < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Replaces all the labels for a labelable object."

      visibility :internal
      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The id of the labelable object to replace the labels for.", required: true, loads: Interfaces::Labelable
      argument :labels, [Inputs::AddOrCreateLabelsLabelInput], "The label attributes to replace the existing labels.", required: true

      read_arguments_from_replicas!

      error_fields
      field :labelable_record, Interfaces::Labelable, "The item that was labeled.", null: true

      def resolve(labelable:, **inputs)
        record = labelable
        issue = record.is_a?(PullRequest) ? record.issue : record

        read_from_selected_replicas([ApplicationRecord::Repositories]) do
          unless issue.labelable_by?(actor: context[:viewer])
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to manage labels in this repository.")
          end

          issue.async_repository.then do |repository|
            if record.is_a?(Issue) && !repository.has_issues?
              raise Errors::Unprocessable::IssuesDisabled.new
            end

            if repository.locked_on_migration?
              raise Errors::Unprocessable::RepositoryMigration.new
            end

            if repository.archived?
              raise Errors::Unprocessable::RepositoryArchived.new
            end

            label_names = inputs[:labels].map { |l| l[:name] }
            labels_to_add = if GitHub.flipper[:issue_dependency_removal].enabled?
              Issues.domain.labels.by_repository_and_names(repository_id: repository.id, names: label_names)
            else
              repository.find_labels_by_name(label_names).to_a
            end
            existing_label_names = labels_to_add.map(&:lowercase_name)

            inputs[:labels].each do |label|
              unless existing_label_names.include?(label[:name].downcase)
                # If the user doesn't have repo write access, skip creating the label
                if GitHub.flipper[:issue_skip_create_label_if_repo_not_writeable].enabled?
                  next unless repository.writable_by?(@context[:viewer])
                end

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

            if labels_to_add.any?(&:invalid?)
              next {
                labelable_record: nil,
                errors: Platform::UserErrors.mutation_errors_for_models(labels_to_add, path_prefix: %w[input labels]),
              }
            end
            labels_to_add.each do |label|
              if label.new_record?
                label.save
              end
            end
            issue.replace_labels(labels_to_add)

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
end
