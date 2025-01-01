# typed: true
# frozen_string_literal: true

module SettingsCollection
  # We pass an instance of this class to the AR `attribute` class macro.
  # it is the codec between rails and the db.
  class JsonColumnType < ActiveModel::Type::Value
    # The generated ActiveModel class which contains the attributes to be stored in the column
    attr_reader :collection_model

    def initialize(collection_model:)
      @collection_model = collection_model
      super()
    end

    def type
      :json
    end

    # https://api.rubyonrails.org/classes/ActiveModel/Type/Value.html#method-i-cast
    # Takes a value from the database or user input
    # This method works in concert with the model class to hydrate instances
    # of that class from the database.
    def cast(value)
      case value
      when String
        # we want to filter keys that aren't attributes. This is pretty much
        # inlining ActiveSupport::JSON.from_json with a bit of tweaking
        hash = ActiveSupport::JSON.decode(value).filter do |k, _v|
          collection_model.attribute_names.include?(k.to_s)
        end

        collection_model.from_json(hash)
      when Hash
        hash = value.filter do |k, _v|
          collection_model.attribute_names.include?(k.to_s)
        end

        collection_model.from_json(hash)
      when collection_model
        value
      when nil
        collection_model.new
      end
    end

    # https://api.rubyonrails.org/classes/ActiveModel/Type/Value.html#method-i-serialize
    # Turns the type into something we can put in the database
    # We only serialize attributes with non-default values. If every value is its default,
    # we'll save a "{}" string to the database.
    #
    # Serializing the whole model to the database will likely only happen for brand new records.
    # Normally we'll update model attributes directly using the `set!` method defined in `UserSettings`,
    # which uses a MySQL function to update the JSON column.
    def serialize(value)
      json_hash = case value
      when collection_model
        value.as_json.reject do |k, v|
          collection_model.is_default_value?(k, v)
        end
      else
        raise ArgumentError, "Unexpected type #{value.class.name}"
      end
      ActiveSupport::JSON.encode(json_hash)
    end

    def changed_in_place?(raw_old_value, new_value)
      cast(raw_old_value) != new_value
    end
  end
end
