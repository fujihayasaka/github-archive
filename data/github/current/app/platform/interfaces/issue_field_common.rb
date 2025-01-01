# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module IssueFieldCommon
      include Platform::Interfaces::Base
      description "Common fields across different issue field types"

      field :name, String, "The issue field's name.", null: false
      sig { returns(String) }
      def name
        @object.name
      end

      field :data_type, Enums::IssueFieldDataType, "The issue field's data type.", null: false
      sig { returns(Symbol) }
      def data_type
        if @object.data_type == "text"
          T.must(Enums::IssueFieldDataType.values["TEXT"]).value
        elsif @object.data_type == "single_select"
          T.must(Enums::IssueFieldDataType.values["SINGLE_SELECT"]).value
        else
          raise Platform::Errors::Internal, "Unexpected issue field data type: #{@object.data_type.inspect}"
        end
      end
    end
  end
end
