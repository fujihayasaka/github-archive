# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldSingleSelect < Platform::Objects::Base
      docs_category :issues
      implements Platform::Interfaces::IssueFieldCommon

      graphql_name "IssueFieldSingleSelect"
      scopeless_tokens_as_minimum

      description "Represents a single select issue field."

      class << self
        # Delegate static methods to the IssueField helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueField
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueField
      end

      implements_node templates: [[:ifss, :id]], as: "IFSS", ready_date: "1970-01-01" do |issue_field_single_select|
        {
          prefix: :ifss,
          id: issue_field_single_select.id
        }
      end

      sig { params(id: T.any(Integer, String)).returns(Promise[T.nilable(::IssueFieldSingleSelect)]) }
      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldSingleSelect, id.to_i, security_violation_behaviour: :nil).then do |field|
          next unless field
          field
        end
      end

      field(:options, [Objects::IssueFieldSingleSelectOption, null: false],
        description: "Options for the single select field",
        null: false,
      )
      def options
        @object.async_options.then do |options|
          sorted = IssueFieldOption.sorted_options(options)
          # When the kill switch is active revert to the plain list (no wrapping). When off,
          # wrap each option with the parent field so that async_viewer_can_see? has repository
          # context. The platform calls async_viewer_can_see? per item even for plain list fields
          # when the item type implements Node. Without the wrapper the access check falls back to
          # the org-level path (requires read:org scope), which blocks non-members using only
          # public_repo scope from seeing options on public repos.
          next ArrayWrapper.new(sorted) unless IssueFieldsFeature.repo_issue_fields_enabled?(actor: @context[:viewer])

          ArrayWrapper.new(sorted.map do |opt|
            Platform::Models::IssueFieldOptionWithFieldContext.new(opt, field: @object)
          end)
        end
      end
    end
  end
end
