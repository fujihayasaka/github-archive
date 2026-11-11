# typed: strict
# frozen_string_literal: true

class IssueField
  module Defaults
    FIELDS = T.let([
      {
        name: "Priority",
        description: "Current importance level assigned to this issue",
        data_type: "single_select",
        priority: 1,
        options: [
          { name: "Urgent", color: :pink, priority: 1 },
          { name: "High", color: :red, priority: 2 },
          { name: "Medium", color: :yellow, priority: 3 },
          { name: "Low", color: :green, priority: 4 },
        ],
      },
      {
        name: "Start date",
        description: "Date when work on issue will begin",
        data_type: "date",
        priority: 2,
      },
      {
        name: "Target date",
        description: "Expected completion date for this issue",
        data_type: "date",
        priority: 3,
      },
      {
        name: "Effort",
        description: "Relative level of effort for completing this issue",
        data_type: "single_select",
        priority: 4,
        options: [
          { name: "High", color: :red, priority: 1 },
          { name: "Medium", color: :yellow, priority: 2 },
          { name: "Low", color: :green, priority: 3 },
        ],
      },
    ].freeze, T::Array[T::Hash[T.any(String, Symbol), T.untyped]])

    FIELD_MAPPINGS = T.let({
      "Bug" => %w[Priority Effort],
      "Feature" => ["Priority", "Start date", "Target date", "Effort"],
      "Task" => %w[Priority Effort],
    }.freeze, T::Hash[String, T::Array[String]])

    DEFAULT_TYPE_FIELDS = T.let(["Priority"].freeze, T::Array[String])

    sig { params(org: Orgs::IOrganization).void }
    def self.create_default_issue_fields_for(org)
      return if IssueField.where(owner: org).exists?

      IssueField.transaction do
        created_fields = create_fields_and_options(org)
        issue_types = IssueType.where(owner: org)
        create_field_mappings_for_org(org, created_fields, issue_types)
        pin_priority_to_no_type_issues(org, created_fields)
      end
    end

    sig { params(org: Orgs::IOrganization).returns(T::Hash[String, IssueField]) }
    def self.create_fields_and_options(org)
      system_actor = User.ghost
      created_fields = T.let({}, T::Hash[String, IssueField])

      FIELDS.each do |field_data|
        field_result = if field_data[:data_type] == "single_select"
          options = T.cast(field_data[:options], T::Array[T::Hash[Symbol, T.untyped]]).map do |option_data|
            Issues::IssueFieldOptionNewAttributes.new(
              name: option_data[:name],
              color: option_data[:color].to_s,
              description: nil,
              priority: option_data[:priority],
            )
          end

          Issues.domain.issue_fields.create_single_select_field(
            org: org,
            name: field_data[:name],
            description: field_data[:description],
            priority: field_data[:priority],
            options: options,
            actor: system_actor,
          )
        else
          Issues.domain.issue_fields.create_field(
            org: org,
            name: field_data[:name],
            data_type: field_data[:data_type],
            description: field_data[:description],
            priority: field_data[:priority],
            actor: system_actor,
          )
        end

        if field_result.ok?
          created_fields[field_data[:name]] = T.cast(field_result.unwrap!, IssueField)
        else
          raise "Failed to create issue field #{field_data[:name]} for org #{org.id}"
        end
      end

      created_fields
    end

    sig { params(org: Orgs::IOrganization, created_fields: T::Hash[String, IssueField], issue_types: T.untyped).void }
    def self.create_field_mappings_for_org(org, created_fields, issue_types)
      return if issue_types.empty?

      priority_field = created_fields["Priority"]
      start_date_field = created_fields["Start date"]
      target_date_field = created_fields["Target date"]
      effort_field = created_fields["Effort"]

      return unless priority_field && start_date_field && target_date_field && effort_field

      issue_types.each do |issue_type|
        field_names = FIELD_MAPPINGS.fetch(issue_type.name, DEFAULT_TYPE_FIELDS)
        fields_for_type = field_names.filter_map { |name| created_fields[name] }

        result = Issues.domain.planning_templates.add_bulk_issue_type_fields_mapping(
          org: org,
          issue_type: issue_type,
          issue_fields: fields_for_type,
          positions: nil,
        )

        unless result.ok?
          raise "Failed to create field mapping for issue type #{issue_type.name} for org #{org.id}"
        end
      end
    end

    sig { params(org: Orgs::IOrganization, created_fields: T::Hash[String, IssueField]).void }
    def self.pin_priority_to_no_type_issues(org, created_fields)
      priority_field = created_fields["Priority"]
      return unless priority_field

      result = Issues.domain.planning_templates.set_pinned_issue_fields_for_no_type_issues(
        org: org,
        issue_fields: [priority_field],
        positions: [0],
      )

      unless result.ok?
        raise "Failed to pin Priority field to issues without a type for org #{org.id}"
      end
    end
  end
end
