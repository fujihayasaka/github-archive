# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class IssueFields < GH::Domain::Base
      # Get IssueFields for an organization
      # Accepts optional order_by argument, defaults to :priority
      sig { params(org: Orgs::IOrganization, order_by: T.nilable(Symbol), excluding: T::Array[Integer]).returns(T::Array[IssueField::IssueFieldType]) }
      def by_organization(org, order_by = nil, excluding: [])
        order_column = order_by || :priority
        scope = ::IssueField.where(owner: org).order(order_column)
        if excluding.any?
          scope = scope.where.not(id: excluding)
        end
        scope.map { |field| T.cast(field, IssueField::IssueFieldType) }
      end

      # Get IssueFields for list of organizations
      sig { params(orgs: T::Array[Orgs::IOrganization]).returns(T::Hash[Integer, T::Array[IssueField::IssueFieldType]]) }
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
      sig { params(issue_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[T.any(Issues::IIssueFieldTextValue, Issues::IIssueFieldSingleSelectValue, Issues::IIssueFieldDateValue)]]) }
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

      # Find a IssueFields by IDs and organization
      sig { params(ids: T::Array[Integer], org: Orgs::IOrganization).returns(T::Array[Issues::IIssueField]) }
      def by_organization_and_field_ids(ids:, org:)
        ::IssueField.where(id: ids, owner: org).to_a
      end

      # Get the value of a specific issue field for a given issue, scoped to a repository for sharding
      sig { params(repository_id: Integer, issue_id: Integer, issue_field_id: Integer).returns(T.nilable(IssueFieldValue)) }
      def get_issue_field_value(repository_id, issue_id, issue_field_id)
        IssueFieldValue
          .where(repository_id: repository_id, issue_id: issue_id, issue_field_id: issue_field_id)
          .includes(:issue_field, issue_field: :options)
          .first
      end

      # Create an IssueField for the given org, name, and data_type
      # data_type should be a string matching the enum key (e.g., "text" or "single_select")
      sig do
        params(
          org: Orgs::IOrganization,
          name: String,
          data_type: String,
          actor: User,
          description: T.nilable(String),
          priority: T.nilable(Integer)
        ).returns(GH::Result[Issues::IIssueField])
      end
      def create_field(org:, name:, data_type:, actor:, description: nil, priority: nil)
        begin
          field = create_field_record(org: org, name: name, data_type: data_type, actor: actor, description: description, priority: priority)
          GH::Result::Ok.new(field)
        rescue ActiveRecord::RecordInvalid => e
          GH::Result::Error::Validation.new(e.record, message: "Validation failed")
        rescue ActiveRecord::ActiveRecordError => e
          GH::Result::Error.new("Failed to create issue field: #{e.message}")
        end
      end

      # Create a single_select IssueField with options in a transaction
      sig do
        params(
          org: Orgs::IOrganization,
          name: String,
          options: T::Array[Issues::IssueFieldOptionNewAttributes],
          actor: User,
          description: T.nilable(String),
          priority: T.nilable(Integer)
        ).returns(GH::Result[Issues::IIssueField])
      end
      def create_single_select_field(org:, name:, options:, actor:, description: nil, priority: nil) # rubocop:disable Metrics/MethodLength
        IssueField.transaction do
          field = create_field_record(org: org, name: name, data_type: "single_select", actor: actor, description: description, priority: priority)
          create_options_for_field(field: field, options: options, org: org)
          GH::Result::Ok.new(field)
        end
      rescue ActiveRecord::RecordInvalid => e
        GH::Result::Error::Validation.new(e.record, message: "Validation failed")
      rescue ActiveRecord::ActiveRecordError => e
        GH::Result::Error.new("Failed to create single select field: #{e.message}")
      end

      # Update an IssueField with new attributes
      sig do
        params(
          issue_field: IIssueField,
          field_attributes: Issues::IssueFieldUpdateAttributes,
          org: Orgs::IOrganization
        ).returns(GH::Result[Issues::IIssueField])
      end
      def update_field(issue_field:, field_attributes:, org:)
        # Find the issue field and ensure it belongs to the organization
        updated = update_field_record(issue_field, field_attributes)
        return GH::Result::Error::Validation.new(updated) if updated.errors.any?

        GH::Result::Ok.new(updated)
      rescue ActiveRecord::ActiveRecordError => e
        GH::Result::Error.new("Failed to update issue field: #{e.message}")
      end

      # Update an IssueField with new attributes
      # all_options is a hash of form encoded params where keys indices
      # It represents all the desired final options for the field.
      sig do
        params(
          issue_field: IIssueFieldSingleSelect,
          field_attributes: T.nilable(Issues::IssueFieldUpdateAttributes),
          all_options: T::Array[IssueFieldOptionUpdateAttributes],
          org: Orgs::IOrganization
        ).returns(GH::Result[Issues::IIssueFieldSingleSelect])
      end
      def update_single_select_field(issue_field:, field_attributes:, all_options:, org:) # rubocop:disable Metrics/MethodLength
        return GH::Result::Error.new("Single select field #{issue_field.name} must have at least one option") unless all_options.any?
        new_options = all_options
          .filter { |option| option.option_id.to_s == "0" }
          .map do |option|
            Issues::IssueFieldOptionNewAttributes.new(
              name: option.name,
              color: option.color,
              description: option.description,
              priority: option.priority
            )
          end
        update_options = all_options
          .filter { |option| option.option_id.to_s != "0" }
          .filter do |option|
            existing_option = issue_field.options.find { |o| o.id.to_s == option.option_id.to_s }
            next false unless existing_option

            # Only update if the option exists and has changed
            option.name != existing_option.name ||
              option.color.downcase != existing_option.color.downcase ||
              option.description != existing_option.description ||
              option.priority != existing_option.priority
          end

        delete_options = (issue_field.options.map(&:id) - all_options.map { |option| option.option_id.to_i }).compact

        IssueField.transaction do
          updated_field = update_field_record(issue_field, field_attributes)

          return GH::Result::Error::Validation.new(updated_field) if updated_field.errors.any?
          create_options_for_field(field: updated_field, options: new_options, org: org) if new_options.any?
          update_options_for_field(field: updated_field, options: update_options, org: org) if update_options.any?
          delete_options_for_field(field: updated_field, options: delete_options, org: org) if delete_options.any?

          GH::Result::Ok.new(updated_field.reload)
        end
      rescue ActiveRecord::RecordInvalid => e
        GH::Result::Error::Validation.new(e.record, message: e.message)
      rescue ActiveRecord::ActiveRecordError => e
        GH::Result::Error.new("Failed to update single select field: #{e.message}")
      end

      # Find an IssueFieldOption by ID, ensuring it belongs to the given issue_field and organization
      sig do
        params(
          option_id: T.any(String, Integer),
          issue_field_id: T.any(String, Integer),
          org: Orgs::IOrganization
        ).returns(GH::Result[Issues::IIssueFieldOption])
      end
      def find_field_option_by_organization(option_id:, issue_field_id:, org:)
        # First ensure the issue field belongs to the organization
        issue_field = ::IssueField.where(id: issue_field_id, owner: org).first
        return GH::Result::Error::NotFound.new("Issue field not found") unless issue_field

        # Then find the option that belongs to that issue field
        option = ::IssueFieldOption.where(id: option_id, issue_field: issue_field).first
        if option
          GH::Result::Ok.new(option)
        else
          GH::Result::Error::NotFound.new("Issue field option not found")
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

      # get an IssueField by id and owner (org)
      sig { params(id: Integer, org: Orgs::IOrganization).returns(T.nilable(Issues::IIssueField)) }
      def issue_field_for_org(id, org)
        ::IssueField.find_by(id: id, owner: org)
      end

      # Query for a set of issue fields by their IDs for a specific organization.
      sig do
        params(
          ids: T::Array[Integer],
          owner: Orgs::IOrganization,
        ).returns(T::Array[IssueField::IssueFieldType])
      end
      def issue_fields_for_org(ids:, owner:)
        ::IssueField.where(id: ids, owner:)
          .map { |field| T.cast(field, IssueField::IssueFieldType) }
      end

      # delete an issue field by id and owner
      sig { params(id: Integer, org: Orgs::IOrganization).returns(GH::Result[Issues::IIssueField]) }
      def delete_field_by_id(id, org)
        issue_field = ::IssueField.find_by(id: id, owner: org)
        return GH::Result::Error::NotFound.new("Issue field not found") unless issue_field

        destroy_issue_field(issue_field)
      end

      private

      sig { params(issue_field: IssueField).returns(GH::Result[Issues::IIssueField]) }
      def destroy_issue_field(issue_field)
        begin
          issue_field.destroy!
          GH::Result::Ok.new(issue_field)
        rescue ActiveRecord::RecordInvalid => e
          GH::Result::Error::Validation.new(issue_field, message: "Validation failed: #{e.message}")
        rescue ActiveRecord::RecordNotDestroyed => e
          GH::Result::Error::Validation.new(issue_field, message: "Failed to delete issue field: #{e.message}")
        rescue ActiveRecord::ActiveRecordError => e
          GH::Result::Error.new("Database error occurred while deleting issue field: #{e.message}")
        end
      end

      sig do
        params(
          org: Orgs::IOrganization,
          name: String,
          data_type: String,
          actor: User,
          description: T.nilable(String),
          priority: T.nilable(Integer)
        ).returns(IssueField)
      end
      def create_field_record(org:, name:, data_type:, actor:, description: nil, priority: nil)
        IssueField.create!(
          owner: org,
          name: name,
          data_type: data_type,
          actor: actor,
          description: description,
          priority: priority
        )
      end

      sig { params(field: IIssueField, field_attributes: T.nilable(Issues::IssueFieldUpdateAttributes)).returns(IssueField) }
      def update_field_record(field, field_attributes)
        update_attrs = {}
        update_attrs[:name] = field_attributes&.name if field_attributes.respond_to?("name")
        update_attrs[:description] = field_attributes&.description
        update_attrs[:priority] = field_attributes&.priority if  field_attributes.respond_to?("priority")

        if update_attrs.any?
          IssueField.update!(field.id, update_attrs)
        else
          field
        end
      end

      sig do
        params(
          field: IssueField,
          options: T::Array[Issues::IssueFieldOptionNewAttributes],
          org: Orgs::IOrganization
        ).void
      end
      def create_options_for_field(field:, options:, org:)
        options.each do |field_option_attributes|
          IssueFieldOption.create!(
          issue_field: field,
          name: field_option_attributes.name,
          color: field_option_attributes.color,
          description: field_option_attributes.description,
          priority: field_option_attributes.priority,
          owner: org
        )
        end
      end

      sig do
        params(
          field: IssueField,
          options: T::Array[Issues::IssueFieldOptionUpdateAttributes],
          org: Orgs::IOrganization
        ).void
      end
      def update_options_for_field(field:, options:, org:)
        options.each do |field_option_attributes|
          option = field.options.find { |o| o.id.to_s == field_option_attributes.option_id.to_s }

          update_attrs = {}
          update_attrs[:name] = field_option_attributes.name if field_option_attributes.name.present?
          update_attrs[:color] = field_option_attributes.color if field_option_attributes.color.present?
          update_attrs[:description] =
            field_option_attributes.description unless field_option_attributes.description.nil?
          update_attrs[:priority] =
          field_option_attributes.priority unless field_option_attributes.priority.nil?

          T.must(option).update!(update_attrs)
        end
      end

      sig do
        params(
          field: IssueField,
          options: T::Array[Integer],
          org: Orgs::IOrganization
        )
        .void
      end
      def delete_options_for_field(field:, options:, org:)
        changed = T.let(false, T::Boolean)
        options.each do |option_id|
          option = field.options.find { |o| o.id.to_s == option_id.to_s }
          if option
            option.destroy
            changed = true
          else
            raise ActiveRecord::RecordNotFound, "Option with ID #{option_id} not found in field #{field.id}"
          end
        end
      end
    end
  end
end
