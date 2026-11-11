# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectV2Field
      # Given a ProjectField (MemexProjectColumn) coerce this
      # into a specific field type.
      #
      def self.coerce(field)
        case field.data_type
        when "single_select"
          Platform::Models::SingleSelectField.new(field)
        when "iteration"
          Platform::Models::IterationField.new(field)
        else
          field
        end
      end

      # Returns a Promise<Boolean>. Hides :org_only issue field columns on public projects.
      def self.async_issue_field_column_visible_to?(permission, object)
        object.async_memex_project.then do |project|
          next false unless project
          project.async_owner.then do
            project.async_business.then do
              next false unless IssueFieldsFeature.enabled?(project, actor: permission.viewer)
              Platform::Helpers::IssueFieldVisibility.async_visible_on_project_surfaces?(
                project: project,
                issue_field_id: object.issue_field_id,
              )
            end
          end
        end
      end

      # Field types share template generate for global ids
      # allowing us to reuse a single method for generation.
      def self.generate_id_template(prefix, field)
        field.async_memex_project.then do |project|
          refined_prefix = case project.owner_type
          when "Organization"
            prefix.org
          when "User"
            prefix.user
          else
            raise Platform::Errors::Internal, "Unexpected project owner: #{project.owner_type.inspect}"
          end
          { prefix: refined_prefix, owner_id: project.owner_id, project_id: project.id, id: field.id }
        end
      end

      # Creates a generic ProjectV2Field type definition that is used in
      # the different types of field (ProjectV2Field, ProjectV2IterationField,
      # ProjectV2SingleSelectField etc.).
      # Taking in an instance of a Prefix (Platform::Helpers::ProjectV2::Prefix)
      # this method returns a block (proc) that is called in each of the types invoking
      # elements of the platform node DSL.
      #
      def self.generic_definition(prefix)
        proc { |definition|
          definition.implements Platform::Interfaces::ProjectV2FieldCommon

          definition.model_name "MemexProjectColumn"

          definition.implements_node templates: [
              [prefix.org, :owner_id, :project_id, :id],
              [prefix.user, :owner_id, :project_id, :id]
            ],
            as: prefix.to_s,
            ready_date: "1970-01-01" do |field|
              self.generate_id_template(prefix, field)
            end

          definition.visibility :public, environments: [:dotcom, :enterprise]

          definition.minimum_accepted_scopes ["read:project"]
        }
      end
    end
  end
end
