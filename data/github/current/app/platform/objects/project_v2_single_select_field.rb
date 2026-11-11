# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2SingleSelectField < Platform::Objects::Base
      docs_category :projects
      extend T::Helpers
      description "A single select field inside a project."

      class << self
        delegate :load_from_global_id, to: Models::SingleSelectField
      end

      def self.async_api_can_access?(permission, object)
        object.async_memex_project.then do |project|
          next false unless project
          if object.issue_field?
            Platform::Helpers::ProjectV2Field.async_issue_field_column_visible_to?(permission, object).then do |visible|
              next false unless visible
              permission.typed_can_access?("ProjectV2", project)
            end
          else
            permission.typed_can_access?("ProjectV2", project)
          end
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_memex_project.then do |project|
          next false unless project
          if object.issue_field?
            Platform::Helpers::ProjectV2Field.async_issue_field_column_visible_to?(permission, object).then do |visible|
              next false unless visible
              permission.typed_can_see?("ProjectV2", project)
            end
          else
            permission.typed_can_see?("ProjectV2", project)
          end
        end
      end

      Platform::Helpers::ProjectV2Field
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTSSF", :opvtssf, :upvtssf)
        )
        .call(self)

      field :issue_field, Platform::Unions::IssueFields,
        description: "The organization issue field associated with this project field, if any",
        null: true,
        feature_flag: IssueFieldsFeature::ISSUE_FIELDS_FLAG
      def issue_field
        return unless object.issue_field?
        Platform::Loaders::ActiveRecord
          .load(::IssueField, object.issue_field_id)
          .then do |issue_field|
            next unless issue_field
            # Loading async_owner prevents an N+1 query when resolving the issue field's organization owner later
            issue_field.async_owner.then { issue_field }
          end
      end

      field(:options, [Objects::ProjectV2SingleSelectFieldOption, null: false],
        description: "Options for the single select field",
        null: false,
      ) do
        T.bind(self, GraphQL::Schema::Field)
        argument :names, [String], "Filter returned options to only those matching these names, case " \
          "insensitive.", required: false
      end

      def options(names: nil)
        ArrayWrapper.new(@object.options(names: names))
      end
    end
  end
end
