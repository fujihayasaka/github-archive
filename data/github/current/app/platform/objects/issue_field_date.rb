# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldDate < Platform::Objects::Base
      implements Platform::Interfaces::IssueFieldCommon

      graphql_name "IssueFieldDate"
      scopeless_tokens_as_minimum
      feature_flag :issue_fields

      description "Represents a date issue field."

      class << self
        # Delegate static methods to the IssueField helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueField
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueField
      end

      implements_node templates: [[:ifd, :id]], as: "IFD", ready_date: "1970-01-01" do |issue_field_date|
        {
          prefix: :ifd,
          id: issue_field_date.id
        }
      end

      sig { params(id: T.any(Integer, String)).returns(Promise[T.nilable(::IssueFieldDate)]) }
      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldDate, id.to_i, security_violation_behaviour: :nil).then do |field|
          next unless field
          field
        end
      end
    end
  end
end
