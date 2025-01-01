# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldSingleSelectOption < Platform::Objects::Base
      scopeless_tokens_as_minimum
      visibility :under_development
      description "Represents an option in a single-select issue field."

      class << self
        # Delegate static methods to the IssueField helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueField
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueField
      end

      field :name, String, "The option's name.", null: false
      field :description, String, "The option's plain-text description.", null: true
      field :color, Enums::IssueFieldSingleSelectOptionColor, "The option's display color.", null: false
      field :priority, Integer, "The option's priority order.", null: true

      implements_node templates: [[:ifsso, :id]], as: "IFSSO", ready_date: "1970-01-01" do |issue_field_single_select_option|
        {
          prefix: :ifsso,
          id: issue_field_single_select_option.id
        }
      end

      sig { params(id: T.any(Integer, String)).returns(Promise[T.nilable(::IssueFieldOption)]) }
      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldOption, id.to_i, security_violation_behaviour: :nil).then do |option|
          next unless option
          option
        end
      end

      def priority
        @object.priority
      end
    end
  end
end
