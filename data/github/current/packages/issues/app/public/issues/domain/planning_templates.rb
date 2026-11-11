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
      sig { params(org: Orgs::IOrganization, issue_type: IssueType, readonly: T::Boolean).returns(T::Array[IIssueField]) }
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

      # Get the pinned issue fields for the organization's default planning template.
      sig { params(org: Orgs::IOrganization, readonly: T::Boolean).returns(T::Array[IIssueField]) }
      def get_pinned_issue_fields_for_org(org:, readonly: false)
        if readonly
          planning_template = get_for_org(org)
          return [] if planning_template.nil?
        else
          planning_template = get_or_create_default_for_org(org)
        end

        issue_fields = planning_template.pinned_fields
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
        if positions.present? && positions.size != issue_fields.size
          return GH::Result::Error::Argument.new(
            "Positions array size (#{positions.size}) must match issue_fields array size (#{issue_fields.size})"
          )
        end

        valid_positions = positions || (0...issue_fields.size).to_a
        begin
          PlanningTemplatesTypeFieldsMapping.transaction do
            pt = get_or_create_default_for_org(org)

            PlanningTemplatesTypeFieldsMapping.where(
              owner: org,
              planning_template: get_or_create_default_for_org(org),
              issue_type: issue_type).delete_all

            issue_fields.each_with_index do |issue_field, index|
              create_type_field_mapping_record(
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

      # Add pinned issue fields to the organization's default planning template for issues without a type.
      # If the organization's default planning template does not exist, it is created.
      # Parameters:
      # - org: The organization for which the pinned fields are set (Orgs::IOrganization).
      # - issue_fields: An array of issue fields to pin (T::Array[Issues::IIssueField]).
      # - positions: Optional array of positions for the fields (T.nilable(T::Array[Integer])).
      # Returns:
      # - GH::Result[Issues::IPlanningTemplate]: Ok result with the planning template if successful,
      #   or Error result if validation or database errors occur.
      sig do
        params(
          org: Orgs::IOrganization,
          issue_fields: T::Array[IIssueField],
          positions: T.nilable(T::Array[Integer]),
        ).returns(GH::Result[Issues::IPlanningTemplate])
      end
      def set_pinned_issue_fields_for_no_type_issues(org:, issue_fields:, positions:) # rubocop:disable Metrics/MethodLength
        if positions.present? && positions.size != issue_fields.size
          return GH::Result::Error::Argument.new(
            "Positions array size (#{positions.size}) must match issue_fields array size (#{issue_fields.size})"
          )
        end

        valid_positions = positions || (0...issue_fields.size).to_a
        begin
          PlanningTemplatesPinnedField.transaction do
            pt = get_or_create_default_for_org(org)

            # Get existing pinned fields
            existing_pinned_fields = PlanningTemplatesPinnedField.where(
              owner: org,
              planning_template: pt
            ).index_by(&:issue_field_id)

            # Track which issue fields we want to keep
            issue_field_ids_to_keep = issue_fields.map(&:id).to_set

            # Delete records for fields that are no longer in the list
            existing_pinned_fields.each do |field_id, record|
              record.destroy! unless issue_field_ids_to_keep.include?(field_id)
            end

            # Reload after deletions to get fresh state
            existing_pinned_fields = PlanningTemplatesPinnedField.where(
              owner: org,
              planning_template: pt
            ).index_by(&:issue_field_id)

            # Now update or create records
            issue_fields.each_with_index do |issue_field, index|
              position = T.must(valid_positions[index])
              existing = existing_pinned_fields[issue_field.id]

              if existing
                # Update existing record if position changed
                if existing.position != position
                  existing.update!(position: position)
                end
              else
                # Create new record
                create_pinned_field_record(
                  planning_template: pt,
                  owner: org,
                  issue_field: issue_field,
                  position: position,
                )
              end
            end

            GH::Result::Ok.new(pt)
          end
        rescue ActiveRecord::RecordInvalid => e
          GH::Result::Error::Validation.new(e.record, message: "Validation failed: #{e.message}")
        rescue ActiveRecord::ActiveRecordError => e
          GH::Result::Error.new("Failed to set pinned issue fields: #{e.message}")
        end
      end

      # Updates the pinning of a field to specific issue types and/or issues with no type.
      # Parameters:
      # - org: The organization (Orgs::IOrganization).
      # - issue_field: The issue field to pin (Issues::IIssueField).
      # - issue_type_ids: Array of issue type IDs to pin to (T::Array[Integer]).
      # - pinned_to_issues_with_no_type: Boolean indicating if it should be pinned to issues with no type (T::Boolean).
      # Returns:
      # - GH::Result[Issues::IPlanningTemplate]: Ok result with the planning template if successful.
      sig do
        params(
          org: Orgs::IOrganization,
          issue_field: IIssueField,
          issue_type_ids: T::Array[Integer],
          pinned_to_issues_with_no_type: T::Boolean,
        ).returns(GH::Result[Issues::IPlanningTemplate])
      end
      def update_issue_type_pinning_for_field(org:, issue_field:, issue_type_ids:, pinned_to_issues_with_no_type:) # rubocop:disable Metrics/MethodLength
        begin
          PlanningTemplatesTypeFieldsMapping.transaction do
            pt = get_or_create_default_for_org(org)

            # 1. Handle pinning to issues with no type
            update_no_type_pinning_for_field(org: org, issue_field: issue_field, should_pin: pinned_to_issues_with_no_type)

            # 2. Handle issue types
            # Get all mappings for this field in this org/template
            current_mappings = PlanningTemplatesTypeFieldsMapping.where(
              owner: org,
              planning_template: pt,
              issue_field: issue_field
            ).includes(:issue_type)

            current_type_ids = current_mappings.map(&:issue_type_id)
            target_type_ids = issue_type_ids.map(&:to_i)

            to_add = target_type_ids - current_type_ids
            to_remove = current_type_ids - target_type_ids

            # Remove
            if to_remove.any?
              PlanningTemplatesTypeFieldsMapping.where(
                owner: org,
                planning_template: pt,
                issue_field: issue_field,
                issue_type_id: to_remove
              ).delete_all
            end

            # Add
            to_add.each do |type_id|
              issue_type = ::IssueType.find_by(id: type_id, owner: org)
              next unless issue_type

              # Determine position: last for this issue type
              last_position = PlanningTemplatesTypeFieldsMapping.where(
                owner: org,
                planning_template: pt,
                issue_type_id: type_id
              ).maximum(:position) || -1

              create_type_field_mapping_record(
                planning_template: pt,
                issue_type: issue_type,
                issue_field: issue_field,
                position: last_position + 1
              )
            end

            GH::Result::Ok.new(pt)
          end
        rescue ActiveRecord::RecordInvalid => e
          GH::Result::Error::Validation.new(e.record, message: "Validation failed: #{e.message}")
        rescue ActiveRecord::ActiveRecordError => e
          GH::Result::Error.new("Failed to update field pins: #{e.message}")
        end
      end

      # Get the pinning status for a field.
      # Returns a hash with :issue_type_ids and :pinned_to_issues_with_no_type.
      sig { params(org: Orgs::IOrganization, issue_field: IIssueField).returns(T::Hash[Symbol, T.untyped]) }
      def get_pinned_issue_types_for_field(org:, issue_field:)
        pt = get_for_org(org)
        return { issue_type_ids: [], pinned_to_issues_with_no_type: false } unless pt

        # Pinning to issues with no type
        is_pinned_to_no_type = PlanningTemplatesPinnedField.exists?(
          owner: org,
          planning_template: pt,
          issue_field: issue_field
        )

        # Issue types
        issue_type_ids = PlanningTemplatesTypeFieldsMapping.where(
          owner: org,
          planning_template: pt,
          issue_field: issue_field
        ).pluck(:issue_type_id)

        {
          issue_type_ids: issue_type_ids,
          pinned_to_issues_with_no_type: is_pinned_to_no_type
        }
      end

      private

      # Updates the "no type" pinning for a single field.
      # This is more efficient than set_pinned_issue_fields_for_no_type_issues when
      # only modifying a single field's pinning status.
      sig do
        params(
          org: Orgs::IOrganization,
          issue_field: IIssueField,
          should_pin: T::Boolean
        ).void
      end
      def update_no_type_pinning_for_field(org:, issue_field:, should_pin:)
        pt = get_or_create_default_for_org(org)

        existing_record = PlanningTemplatesPinnedField.find_by(
          owner: org,
          planning_template: pt,
          issue_field: issue_field
        )

        if should_pin && existing_record.nil?
          # Add: determine position as last
          last_position = PlanningTemplatesPinnedField.where(
            owner: org,
            planning_template: pt
          ).maximum(:position) || -1

          create_pinned_field_record(
            planning_template: pt,
            owner: org,
            issue_field: issue_field,
            position: last_position + 1
          )
        elsif !should_pin && existing_record.present?
          # Remove
          existing_record.destroy!
        end
      end

      sig do
        params(
          planning_template: PlanningTemplate,
          issue_type: IIssueType,
          issue_field: IIssueField,
          position: Integer,
        ).returns(PlanningTemplatesTypeFieldsMapping)
      end
      def create_type_field_mapping_record(planning_template:, issue_type:, issue_field:, position:)
        PlanningTemplatesTypeFieldsMapping.create!(
          planning_template: planning_template,
          issue_type: issue_type,
          issue_field: issue_field,
          position: position,
        )
      end

      sig do
        params(
          planning_template: PlanningTemplate,
          owner: Orgs::IOrganization,
          issue_field: IIssueField,
          position: Integer,
        ).returns(PlanningTemplatesPinnedField)
      end
      def create_pinned_field_record(planning_template:, owner:, issue_field:, position:)
        PlanningTemplatesPinnedField.create!(
          planning_template: planning_template,
          owner: owner,
          issue_field: issue_field,
          position: position,
        )
      end
    end
  end
end
