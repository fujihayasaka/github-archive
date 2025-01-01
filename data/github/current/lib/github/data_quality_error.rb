# typed: true
# frozen_string_literal: true

module GitHub
  class DataQualityError < StandardError
    def initialize(object, property)
      object_key = object.class.name.dup

      # Get the ActiveRecord ID if possible
      if object.respond_to?(:id)
        object_key << "##{object.id}"
      end

      super "Data Quality error trying to access ##{property} on #{object_key}"
    end
  end
end
