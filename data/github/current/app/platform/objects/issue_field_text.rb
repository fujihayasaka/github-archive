# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldText < Platform::Objects::Base
      implements Platform::Interfaces::IssueFieldCommon

      graphql_name "IssueFieldText"
      scopeless_tokens_as_minimum
      visibility :under_development

      description "Represents a text issue field."

      class << self
        # Delegate static methods to the IssueField helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueField
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueField
      end

      implements_node templates: [[:ift, :id]], as: "IFT", ready_date: "1970-01-01" do |issue_field_text|
        {
          prefix: :ift,
          id: issue_field_text.id
        }
      end

      sig { params(id: T.any(Integer, String)).returns(Promise[T.nilable(::IssueFieldText)]) }
      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldText, id.to_i, security_violation_behaviour: :nil).then do |field|
          next unless field
          field
        end
      end
    end
  end
end
