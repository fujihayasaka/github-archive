# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldMultiSelect < Platform::Objects::Base
      docs_category :issues
      implements Platform::Interfaces::IssueFieldCommon

      graphql_name "IssueFieldMultiSelect"
      scopeless_tokens_as_minimum

      description "Represents a multi select issue field."

      class << self
        # Delegate static methods to the IssueField helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueField
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueField
      end

      implements_node templates: [[:ifms, :id]], as: "IFMS", ready_date: "1970-01-01" do |issue_field_multi_select|
        {
          prefix: :ifms,
          id: issue_field_multi_select.id
        }
      end

      sig { params(id: T.any(Integer, String)).returns(Promise[T.nilable(::IssueFieldMultiSelect)]) }
      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldMultiSelect, id.to_i, security_violation_behaviour: :nil).then do |field|
          next unless field
          field
        end
      end

      field(:options, [Objects::IssueFieldSingleSelectOption, null: false],
        description: "Options for the multi select field",
        null: false,
      )
      def options
        @object.async_options.then do |options|
          sorted = IssueFieldOption.sorted_options(options)
          next ArrayWrapper.new(sorted) unless IssueFieldsFeature.repo_issue_fields_enabled?(actor: @context[:viewer])

          ArrayWrapper.new(sorted.map do |opt|
            Platform::Models::IssueFieldOptionWithFieldContext.new(opt, field: @object)
          end)
        end
      end
    end
  end
end
