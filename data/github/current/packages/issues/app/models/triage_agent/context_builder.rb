# typed: strict
# frozen_string_literal: true

module TriageAgent
  # Builds repository-context strings (labels, issue types, issue fields)
  # for inclusion in triage agent prompts.
  module ContextBuilder
    TRIAGE_CONTEXT_LIMIT = 50

    sig { params(repository: Repository, allowlist: T.nilable(TriageAgent::Allowlist)).returns(String) }
    def self.build_labels_context(repository, allowlist: nil)
      labels = repository.sorted_labels_for_recommendations(limit: TRIAGE_CONTEXT_LIMIT)
      return "No labels configured for this repository." if labels.empty?

      if allowlist&.labels_restricted?
        label_names = labels.map(&:name)
        filtered_names = allowlist.filter_labels(label_names)
        filtered_set = filtered_names.map(&:downcase).to_set
        labels = labels.select { |l| filtered_set.include?(l.name.downcase) }
        return "No labels are allowed for triage. Skip adding labels." if labels.empty?
      end

      label_items = labels.map do |label|
        if label.description.present?
          "`#{label.name}` - description: #{label.description}"
        else
          "`#{label.name}`"
        end
      end

      label_items.join(", ")
    end

    sig { params(repository: Repository, allowlist: T.nilable(TriageAgent::Allowlist)).returns(String) }
    def self.build_issue_types_context(repository, allowlist: nil)
      owner = repository.owner
      return "Issue types are not available for this repository." unless owner&.organization?

      issue_types = Issues.domain.issue_types.by_organization(owner.id)
      issue_types = issue_types.first(TRIAGE_CONTEXT_LIMIT)
      return "No issue types configured for this organization." if issue_types.empty?

      # Cast once up front so we don't repeatedly cast in later loops.
      issue_types = issue_types.map { |it| T.cast(it, ::IssueType) }

      if allowlist&.types_restricted?
        names = issue_types.map(&:name)
        allowed_set = names
          .filter_map { |name| allowlist.filter_type(name)&.downcase }
          .to_set

        issue_types = issue_types.select { |it| allowed_set.include?(it.name.downcase) }
        return "No issue types are allowed for triage. Skip setting issue type." if issue_types.empty?
      end

      type_items = issue_types.map do |issue_type|
        if issue_type.description.present?
          "`#{issue_type.name}` - description: #{issue_type.description}"
        else
          "`#{issue_type.name}`"
        end
      end

      type_items.join(", ")
    end

    sig { params(repository: Repository, allowlist: T.nilable(TriageAgent::Allowlist)).returns(String) }
    def self.build_single_select_issue_fields_context(repository, allowlist: nil)
      owner = repository.owner
      unless owner&.organization? && IssueFieldsFeature.enabled?(owner, context: nil)
        return "Issue fields are not available for this repository. Skip setting issue fields."
      end

      # Only include single_select fields - we don't want the LLM generating free text or dates
      issue_fields = IssueFieldSingleSelect.where(owner: owner).order(:priority).limit(TRIAGE_CONTEXT_LIMIT).to_a
      if issue_fields.empty?
        return "No issue fields configured for this organization. Skip setting issue fields."
      end

      if allowlist&.fields_restricted?
        field_hashes = issue_fields.map { |f| { name: f.name } }
        allowed_hashes = allowlist.filter_fields(field_hashes)
        allowed_set = allowed_hashes.filter_map { |h| h[:name]&.to_s&.downcase }.to_set
        issue_fields = issue_fields.select { |f| allowed_set.include?(f.name.downcase) }
        return "No issue fields are allowed for triage. Skip setting issue fields." if issue_fields.empty?
      end

      field_items = issue_fields.map do |issue_field|
        build_issue_field_item(issue_field)
      end

      field_items.join("; ")
    end

    sig { params(issue_field: IssueField::IssueFieldType).returns(String) }
    def self.build_issue_field_item(issue_field)
      parts = []
      parts << "`#{issue_field.name}` (#{issue_field.data_type})"
      parts << "description: #{issue_field.description}" if issue_field.description.present?

      # For single_select fields, include the available options
      if issue_field.is_a?(IssueFieldSingleSelect)
        options = issue_field.options.to_a
        if options.any?
          option_items = options.map do |opt|
            if opt.description.present?
              "`#{opt.name}` - description: #{opt.description}"
            else
              "`#{opt.name}`"
            end
          end
          parts << "options: [#{option_items.join(", ")}]"
        end
      end

      parts.join(", ")
    end
  end
end
