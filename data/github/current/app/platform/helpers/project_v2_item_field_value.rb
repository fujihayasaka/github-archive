# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectV2ItemFieldValue

      # A factory used to instantiate the corresponding model from the value, item, and field
      # value can be either a `MemexProjectColumnValue`, a special model (i.e. user), or a list of special models.
      # The special models are used to represent the values that are stored on the underlying model.
      #
      # For special model values, the field is passed to the model allowing this to be returned.
      # For `MemexProjectColumnValue` instances the field method is called directly on this.
      def self.coerce(value, item, field)
        return nil if value.blank? || field.nil?

        case field.data_type
        when "text", "title"
          Platform::Models::ProjectItemFieldTextValue.new(value)
        when "number"
          Platform::Models::ProjectItemFieldNumberValue.new(value)
        when "date"
          Platform::Models::ProjectItemFieldDateValue.new(value)
        when "single_select"
          option = field.single_select_option_object(value.value)

          return nil if option.nil?
          Platform::Models::ProjectItemFieldSingleSelectValue.new(value, option)
        when "iteration"
          iteration = field.settings_all_iteration(value.value)

          return if iteration.nil?
          Platform::Models::ProjectItemFieldIterationValue.new(value, iteration)
        when "assignees"
          Platform::Models::ProjectItemFieldUserValue.new(Array.wrap(value), item, field)
        when "repository"
          Platform::Models::ProjectItemFieldRepositoryValue.new(value, item, field)
        when "labels"
          Platform::Models::ProjectItemFieldLabelValue.new(Array.wrap(value), item, field)
        when "milestone"
          Platform::Models::ProjectItemFieldMilestoneValue.new(value, item, field)
        when "linked_pull_requests"
          Platform::Models::ProjectItemFieldPullRequestValue.new(Array.wrap(value), item, field)
        when "reviewers"
          Platform::Models::ProjectItemFieldReviewerValue.new(Array.wrap(value), item, field)
        else
          nil
        end
      end

      # Given a MemexProjectItem argument, return a list of refined values. Each value has a model
      # that represents it in the Platform::Models namespace, and a corresponding ProjectV2 Platform::Object.
      # For special values that are stored on the underlying model, perform additional async logic to prepare these
      # values
      def self.async_refine_item_values(item, viewer, cap_filter, field_name: nil)
        item.async_memex_project.then do |project|
          promise = if field_name.nil?
            project.async_memex_project_columns
          else
            project.async_owner.then do |owner|
              Platform::Loaders::MemexProjectColumnByName.load(project, owner, field_name, viewer)
            end
          end

          promise.then do |fields|
            columns_by_id = fields.index_by(&:id)
            unless field_name.nil?
              fields = fields.filter { |field| field.name == field_name }
              next ArrayWrapper.new([]) if fields.empty?
            end

            allow_repository = field_name.nil? || field_name == MemexProjectColumn::REPOSITORY_COLUMN_NAME
            allow_assignees = field_name.nil? || field_name == MemexProjectColumn::ASSIGNEES_COLUMN_NAME
            allow_labels = field_name.nil? || field_name == MemexProjectColumn::LABELS_COLUMN_NAME
            allow_milestone = field_name.nil? || field_name == MemexProjectColumn::MILESTONE_COLUMN_NAME
            allow_reviewers = field_name.nil? || field_name == MemexProjectColumn::REVIEWERS_COLUMN_NAME

            # Special fields are saved on the items underlying model
            item.async_content.then do |content|
              Promise.all([
                self.async_getter_method(content, :async_repository, allow_repository),
                self.async_getter_method(content, :async_assignees, allow_assignees),
                self.async_getter_method(content, :async_issue),
                self.async_getter_method(content, :async_labels, allow_labels),
                self.async_getter_method(content, :async_milestone, allow_milestone && !self.is_denormalized?("milestone", viewer)),
                self.async_getter_method(content, :async_review_requests, allow_reviewers),
              ]).then do |repository, assignees, issue, labels, milestone, review_requests|
                assignees_promise = Promise.resolve(assignees || [])
                labels_promise = Promise.resolve(labels)
                milestone_promise = Promise.resolve(milestone)

                # For pull requests, these have to be loaded from the underlying issue that backs the pull request
                if issue.present?
                  assignees_promise = issue.async_assignees if allow_assignees && assignees.nil?
                  labels_promise = issue.async_labels if allow_labels && labels.nil?
                  milestone_promise = issue.async_milestone if allow_milestone && !self.is_denormalized?("milestone", viewer) && milestone.nil?
                end

                # Load the pull requests using the cap_filtered async method to ensure authorization is checked
                linked_pull_requests_promise = if content.is_a?(::Issue) && (field_name.nil? || field_name == MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME)
                  content.async_cap_filtered_closed_by_pull_requests_references_for(viewer: viewer, cap_filter: cap_filter)
                else
                  Promise.resolve([])
                end

                # For reviewers these have to be loaded through the review_requests pull request association
                reviewers_promise = if review_requests.present? && content.is_a?(::PullRequest)
                  review_requests.map { |request| request.async_reviewer }
                else
                  Promise.resolve([])
                end

                # Load these additional fields
                Promise.all([assignees_promise, labels_promise, milestone_promise, linked_pull_requests_promise, reviewers_promise]).then do |assignees, labels, milestone, pull_requests, reviewers|
                  # Using the coerce factory method, create a list of field values
                  found_fields = []
                  results = {
                    "assignees" => assignees.flatten,
                    "repository" => repository,
                    "labels" => labels,
                    "milestone" => milestone,
                    "linked_pull_requests" => pull_requests,
                    "reviewers" => reviewers
                  }.map do |data_type, value|
                    field = fields.find { |field| field.data_type == data_type }
                    next if field.nil?

                    found_fields << field
                    self.coerce(value, item, field)
                  end

                  # Filter out any found fields
                  fields = fields.difference(found_fields)

                  # For custom values, such as text, number, date etc. these can be loaded through the column values
                  # association
                  item.async_memex_project_column_values.then do |values|
                    # Use the coerce factory method to refine the values
                    Promise.all(
                      values.map do |value|
                        column = columns_by_id[value.memex_project_column_id]
                        column_promise = if column.present?
                          Promise.resolve(column)
                        else
                          value.async_memex_project_column
                        end

                        column_promise.then do |field|
                          next if field.nil? ||
                            found_fields.include?(field) ||
                            (field_name.present? && field.name != field_name)

                          found_fields << field
                          self.async_coerce_denormalized_field_value(value, item, field, viewer).then { |value| value }
                        end
                      end
                    ).then do |coerced|
                      # Combine and return all of the values, removing nil values
                      ArrayWrapper.new((results + coerced).compact)
                    end
                  end
                end
              end
            end
          end
        end
      end

      # Field types share template generate for global ids
      # allowing us to reuse a single method for generation.
      def self.generate_id_template(prefix, value)
        value.async_memex_project_item.then do |item|
          item.async_memex_project.then do |project|
            refined_prefix = case project.owner_type
            when "Organization"
              prefix.org
            when "User"
              prefix.user
            else
              raise Platform::Errors::Internal, "Unexpected project owner: #{project.owner_type.inspect}"
            end
            { prefix: refined_prefix, owner_id: project.owner_id, project_id: project.id, item_id: item.id, id: value.id }
          end
        end
      end

      # Creates a generic ProjectV2FieldValue type definition that is used in
      # the different types of field (ProjectV2FieldTextValue etc.).
      # Taking in an instance of a Prefix (Platform::Helpers::ProjectV2::Prefix)
      # this method returns a block (proc) that is called in each of the types invoking
      # elements of the platform node DSL.
      #
      def self.generic_definition(prefix)
        proc { |definition|
          definition.model_name "MemexProjectColumnValue"

          definition.implements_node templates: [
              [prefix.org, :owner_id, :project_id, :item_id, :id],
              [prefix.user, :owner_id, :project_id, :item_id, :id]
            ],
            as: prefix.to_s,
            ready_date: "1970-01-01" do |field|
              self.generate_id_template(prefix, field)
            end

          definition.visibility :public, environments: [:dotcom, :enterprise]

          definition.minimum_accepted_scopes ["read:project"]
        }
      end

      def self.async_api_can_access?(permission, object)
        unless object.respond_to?(:async_memex_project_item)
          raise Platform::Errors::Internal, "object must implement async_memex_project_item"
        end

        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.async_memex_project_item.then do |item|
          permission.typed_can_access?("ProjectV2Item", item).then do |can_access|
            next false unless can_access

            item.async_readable_by_viewer?(permission.viewer)
          end
        end
      end

      def self.async_viewer_can_see?(permission, object)
        unless object.respond_to?(:async_memex_project_item)
          raise Platform::Errors::Internal, "object must implement async_memex_project_item"
        end

        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.async_memex_project_item.then do |item|
          permission.typed_can_see?("ProjectV2Item", item).then do |can_access|
            next false unless can_access

            item.async_readable_by_viewer?(permission.viewer)
          end
        end
      end

      # Try to get the async method from an object, if not return a promise that resolves to nil.
      def self.async_getter_method(object, method_name, allow = true)
        if allow && object.respond_to?(method_name.to_sym)
          object.method(method_name.to_sym).call
        else
          Promise.resolve(nil)
        end
      end

      # Coerce denormalized field values that might be special objects and require additional parsing.
      # For instance milestone is denormalized and returns an id / json blob that needs to be refined to a
      # Milestone object
      def self.async_coerce_denormalized_field_value(value, item, field, viewer)
        denormalized_promise = case field.data_type
        when "milestone"
          if self.is_denormalized?(viewer, "milestone")
            Loaders::ActiveRecord.load(::Milestone, value.value.to_i).then do |milestone|
              self.coerce(milestone, item, field)
            end
          end
        end

        # Either return the denormalized version, or just return a promise that resolves the coerced value
        denormalized_promise || Promise.resolve(self.coerce(value, item, field))
      end

      # Determine if a field is denormalized, this can be through either feature flags or hard coded
      def self.is_denormalized?(viewer, data_type)
        case data_type
        when "milestone"
          true
        else
          false
        end
      end

    end
  end
end
