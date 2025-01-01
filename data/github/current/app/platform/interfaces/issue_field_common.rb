# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module IssueFieldCommon
      include Platform::Interfaces::Base
      description "Common fields across different issue field types"

      feature_flag :issue_fields

      database_id_field(visibility: :internal)

      field :name, String, "The issue field's name.", null: false
      sig { returns(String) }
      def name
        @object.name
      end

      field :description, String, "The issue field's description.", null: true
      sig { returns(T.nilable(String)) }
      def description
        @object.description
      end

      field :data_type, Enums::IssueFieldDataType, "The issue field's data type.", null: false
      sig { returns(Symbol) }
      def data_type
        if @object.data_type == "text"
          T.must(Enums::IssueFieldDataType.values["TEXT"]).value
        elsif @object.data_type == "single_select"
          T.must(Enums::IssueFieldDataType.values["SINGLE_SELECT"]).value
        elsif @object.data_type == "date"
          T.must(Enums::IssueFieldDataType.values["DATE"]).value
        elsif @object.data_type == "number"
          T.must(Enums::IssueFieldDataType.values["NUMBER"]).value
        else
          raise Platform::Errors::Internal, "Unexpected issue field data type: #{@object.data_type.inspect}"
        end
      end

      field :created_at, Scalars::DateTime, "The issue field's creation timestamp.", null: false
      sig { returns(ActiveSupport::TimeWithZone) }
      def created_at
        @object.created_at
      end
    end
  end
end
