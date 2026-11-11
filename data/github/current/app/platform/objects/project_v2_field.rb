# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2Field < Platform::Objects::Base
      description "A field inside a project."

      def self.async_api_can_access?(permission, object)
        object.async_memex_project.then do |project|
          next false unless project
          if object.issue_field?
            # IssueFieldsFeature.enabled? checks the Project Owner and enterprise_managed_user status. Load them async to prevent AssociationRefused errors on that
            project.async_owner.then do
              project.async_business.then do
                next false unless IssueFieldsFeature.enabled?(project, actor: permission.viewer)
                permission.typed_can_access?("ProjectV2", project)
              end
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
            # IssueFieldsFeature.enabled? checks the Project Owner and enterprise_managed_user status. Load them async to prevent AssociationRefused errors on that
            project.async_owner.then do
              project.async_business.then do
                next false unless IssueFieldsFeature.enabled?(project, actor: permission.viewer)
                permission.typed_can_see?("ProjectV2", project)
              end
            end
          else
            permission.typed_can_see?("ProjectV2", project)
          end
        end
      end

      # Call the generic definition method and invoke the returned block.
      # This will invoke methods in the Platform base object DSL that are
      # shared between all field types.
      Platform::Helpers::ProjectV2Field
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTF", :opvtf, :upvtf)
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
    end
  end
end
