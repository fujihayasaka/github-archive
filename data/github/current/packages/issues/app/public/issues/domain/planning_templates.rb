# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class PlanningTemplates < GH::Domain::Base
      # Get the default PlanningTemplate for an organization
      sig { params(org: Orgs::IOrganization).returns(PlanningTemplate) }
      def get_or_create_default_for_org(org)
        ::PlanningTemplate.where(owner: org, template_type: PlanningTemplate::TEMPLATE_TYPES[:default])
          .first_or_create!(name: "Default Planning Template", description: "Default planning template for #{org.display_login}")
      end

      # Get the default PlanningTemplate for an organization
      sig { params(org: Orgs::IOrganization).returns(T.nilable(PlanningTemplate)) }
      def get_for_org(org)
        ::PlanningTemplate
          .where(owner: org, template_type: PlanningTemplate::TEMPLATE_TYPES[:default])
          .first
      end

      # Get the pinned issue fields for an issue type in the organization's default planning template.
      sig { params(org: Orgs::IOrganization, issue_type: T.untyped, readonly: T::Boolean).returns(T::Array[IIssueField]) }
      def get_pinned_issue_fields_for_default_template(org:, issue_type:, readonly: false)
        if readonly
          planning_template = get_for_org(org)
          return [] if planning_template.nil?
        else
          planning_template = get_or_create_default_for_org(org)
        end

        issue_fields = planning_template.issue_type_fields_mapping
          .where(issue_type: issue_type)
          .includes(:issue_field)
          .order(:position)
          .map(&:issue_field)
          .compact
          .to_a
      end

      # Adds mappings between a planning template's issue type and multiple issue fields for the given organization.
      # If the organization's default planning template does not exist, it is created.
      # Parameters:
      # - org: The organization for which the mappings are created (Orgs::IOrganization).
      # - issue_type: The issue type to associate with the fields (IIssueType).
      # - issue_fields: An array of issue fields to map to the issue type (T::Array[Issues::IIssueField]).
      # Returns:
      # - GH::Result[Issues::IPlanningTemplate]: Ok result with the planning template if successful,
      #   or Error result if validation or database errors occur.
      sig do
        params(
          org: Orgs::IOrganization,
          issue_type: IssueType,
          issue_fields: T::Array[IIssueField],
          positions: T.nilable(T::Array[Integer]),
        ).returns(GH::Result[Issues::IPlanningTemplate])
      end
      def add_bulk_issue_type_fields_mapping(org:, issue_type:, issue_fields:, positions:) # rubocop:disable Metrics/MethodLength
        valid_positions = positions&.size == issue_fields.size ? T.must(positions) : (0...issue_fields.size).to_a
        begin
          PlanningTemplatesTypeFieldsMapping.transaction do
            pt = get_or_create_default_for_org(org)

            PlanningTemplatesTypeFieldsMapping.where(
              owner: org,
              planning_template: get_or_create_default_for_org(org),
              issue_type: issue_type).delete_all

            issue_fields.each_with_index do |issue_field, index|
              create_type_field_mapping_record(
                owner: org,
                planning_template: pt,
                issue_type: issue_type,
                issue_field: issue_field,
                position: T.must(valid_positions[index]),
              )
            end
            GH::Result::Ok.new(pt)
          end
        rescue ActiveRecord::RecordInvalid => e
          GH::Result::Error::Validation.new(e.record, message: "Validation failed: #{e.message}")
        rescue ActiveRecord::ActiveRecordError => e
          GH::Result::Error.new("Failed to create planning template mappings: #{e.message}")
        end
      end

      private

      sig do
        params(
          owner: Orgs::IOrganization,
          planning_template: PlanningTemplate,
          issue_type: IIssueType,
          issue_field: IIssueField,
          position: Integer,
        ).returns(PlanningTemplatesTypeFieldsMapping)
      end
      def create_type_field_mapping_record(owner:, planning_template:, issue_type:, issue_field:, position:)
        PlanningTemplatesTypeFieldsMapping.create!(
          owner: owner,
          planning_template: planning_template,
          issue_type: issue_type,
          issue_field: issue_field,
          position: position,
        )
      end
    end
  end
end
