# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class IssueFields < GH::Domain::Base
      # Get IssueFields for an organization
      sig { params(org: Orgs::IOrganization).returns(T::Array[T.any(Issues::IIssueFieldText, Issues::IIssueFieldSingleSelect)]) }
      def by_organization(org)
        ::IssueField.where(owner: org)
          .order(:priority)
          .map { |field| T.cast(field, T.any(Issues::IIssueFieldText, Issues::IIssueFieldSingleSelect)) }
      end

      # Get IssueFields for list of organizations
      sig { params(orgs: T::Array[Orgs::IOrganization]).returns(T::Hash[Integer, T::Array[T.any(Issues::IIssueFieldText, Issues::IIssueFieldSingleSelect)]]) }
      def by_organizations(orgs)
        issue_fields_by_owner = ::IssueField.where(owner_id: orgs).order(:priority).group_by(&:owner_id)

        results = {}
        orgs.each do |org|
          fields = issue_fields_by_owner[org.id] || []
          results[org.id] = fields
        end
        results
      end

      # Get issue field values from a list of issues
      sig { params(issue_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[T.any(Issues::IIssueFieldTextValue, Issues::IIssueFieldSingleSelectValue)]]) }
      def get_issue_field_values_from_issues(issue_ids)
        issue_field_values = IssueFieldValue
          .where(issue_id: issue_ids)
          .includes(:issue_field, issue_field: :options)

        grouped = issue_field_values.group_by(&:issue_id)

        # Sort each issue's field values by the priority of their associated issue_field
        issue_ids.index_with do |id|
          (grouped[id] || []).sort_by do |value|
            value.issue_field&.priority || 0
          end
        end
      end

      # Create an IssueField for the given org, name, and data_type
      # data_type should be a string matching the enum key (e.g., "text" or "single_select")
      sig do
        params(
          org: Orgs::IOrganization,
          name: String,
          data_type: String,
          actor: User
        ).returns(Issues::IIssueField)
      end
      def create_field(org:, name:, data_type:, actor:)
        IssueField.create!(
          owner: org,
          name: name,
          data_type: data_type,
          actor: actor
        )
      end

      # Create an IssueFieldOption for the given issue_field, name, and color
      # color should be a string matching the enum key (e.g., "gray", "blue", etc.)
      sig do
        params(
          issue_field: Issues::IIssueField,
          name: String,
          color: String,
          actor: User
        ).returns(Issues::IIssueFieldOption)
      end
      def create_field_option(issue_field:, name:, color:, actor:)
        IssueFieldOption.create!(
          issue_field: issue_field,
          name: name,
          color: color,
          owner: issue_field.owner
        )
      end

      # Set a text field value for an issue
      sig do
        params(
          issue_field: Issues::IIssueField,
          issue: Issue,
          value: String,
          actor: User
        ).returns(Issues::IIssueFieldValue)
      end
      def set_text_field_value(issue_field:, issue:, value:, actor:)
        existing = IssueFieldValue.find_by(issue_field: issue_field, issue: issue)
        if existing
          existing.update!(value: value)
          existing
        else
          IssueFieldValue.create!(
            issue: issue,
            issue_field: issue_field,
            value: value,
            data_type: "text",
            actor: actor,
            repository: issue.repository
          )
        end
      end

      # Set a single select field value for an issue
      # value should be an IssueFieldOption
      sig do
        params(
          issue_field: Issues::IIssueField,
          issue: Issue,
          value: Issues::IIssueFieldOption,
          actor: User
        ).returns(Issues::IIssueFieldValue)
      end
      def set_single_select_field_value(issue_field:, issue:, value:, actor:)
        existing = IssueFieldValue.find_by(issue_field: issue_field, issue: issue)
        if existing
          existing.update!(value: value.id)
          existing
        else
          IssueFieldValue.create!(
            issue: issue,
            issue_field: issue_field,
            value: value.id,
            data_type: "single_select",
            actor: actor,
            repository: issue.repository
          )
        end
      end

      # Delete an IssueFieldValue for a given field and issue
      sig do
        params(
          issue_field: Issues::IIssueField,
          issue: Issue
        ).void
      end
      def delete_field_value(issue_field:, issue:)
        value = IssueFieldValue.find_by(issue_field: issue_field, issue: issue)
        value&.destroy!
      end

      # Create multiple issue field values for an issue
      sig do
        params(
          issue: Issue,
          actor: User,
          attributes: T::Array[CreateIssueFieldValueAttributes]
        ).void
      end
      def create_issue_field_values(issue:, actor:, attributes:) # rubocop:disable Metrics/MethodLength
        issue_field_ids = attributes.map(&:field_id)
        issue_fields = IssueField.where(id: issue_field_ids, owner: T.must(issue.repository).owner).index_by(&:id)

        attributes.each do |field_value|
          field_id = field_value.field_id

          issue_field = issue_fields[field_id]
          unless issue_field
            issue.errors.add(:issue_fields, "Issue field with id #{field_id} not found.")
            raise ActiveRecord::Rollback
          end

          if issue_field.data_type_text?
            text_value = field_value.text_value ? field_value.text_value : ""
            Issues.domain.issue_fields.set_text_field_value(
              issue_field: issue_field,
              issue: issue,
              value: T.must(text_value),
              actor: actor
            )
          elsif issue_field.data_type_single_select?
            unless field_value.single_select_option_id
              issue.errors.add(:issue_fields, "Single select option id is required for single select fields.")
              raise ActiveRecord::Rollback
            end

            option = issue_field.options.find { |o| o.id == field_value.single_select_option_id }
            unless option
              issue.errors.add(:issue_fields, "Option '#{field_value.single_select_option_id}' not found for field '#{issue_field.name}'.")
              raise ActiveRecord::Rollback
            end

            Issues.domain.issue_fields.set_single_select_field_value(
              issue_field: issue_field,
              issue: issue,
              value: option,
              actor: actor
            )
          end
        end
      end
    end
  end
end
