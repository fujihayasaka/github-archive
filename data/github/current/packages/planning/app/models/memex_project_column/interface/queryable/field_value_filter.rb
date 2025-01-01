# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Queryable
  # Represents an additional filter that might be applied to a query that an end-user actually submitted.
  #
  # This is typically used to dynamically extend the query for a view with a particular group or slice selection that
  # the user has made in the UI, thereby allowing the client to paginate through items in that group or slice.
  class FieldValueFilter

    sig { returns(MemexProjectColumn::Field::Base) }
    attr_reader :field

    sig { returns(String) }
    attr_reader :field_value

    sig { params(field_object_or_id: T.any(Integer, MemexProjectColumn::Field::Base), field_value: String).void }
    def initialize(field_object_or_id:, field_value:)
      field_object = field_object_or_id
      unless field_object.is_a?(MemexProjectColumn::Field::Base)
        field_object = MemexProjectColumn.find_by(id: field_object_or_id)&.to_field
      end

      raise ArgumentError, "Could not find Field with ID #{field_object_or_id}" unless field_object.present?

      @field = T.let(field_object, MemexProjectColumn::Field::Base)
      @field_value = T.let(field_value, String)
    end

    # Returns a filter for a given field value that is in the same syntax used by our end-users in the Projects filter
    # bar.
    #
    # This is provided as a convenience for extending the query that was actually submitted by an end-user. It is
    # typically used when paginating through the items in a particular group or slice.
    sig { returns(String) }
    def filter_term = field.field_value_filter(field_value)
  end
end
