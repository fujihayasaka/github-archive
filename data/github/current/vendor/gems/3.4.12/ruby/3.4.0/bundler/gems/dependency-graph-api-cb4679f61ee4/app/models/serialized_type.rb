require "active_record_enumerated_type"

module SerializedType
  def self.included(base)
    base.extend(ClassMethods)
  end

  def serialize
    send(self.class.serialized_attr)
  end

  def to_i
    send(self.class.serialized_attr)
  end

  def quoted_id
    serialize
  end

  module ClassMethods
    def serialize_by(attr)
      @serialized_attr = attr
    end

    def serialized_attr
      @serialized_attr ||= :id
    end

    def names_by_serialized_attr
      @names_by_serialized_attr ||= {}
    end

    def declare(name, options)
      unless options.has_key?(serialized_attr)
        raise "`:#{serialized_attr}` is required for serialization"
      end

      serialized_attr_for_name = options[serialized_attr]
      if names_by_serialized_attr.has_key?(serialized_attr_for_name)
        raise "#{serialized_attr} of #{serialized_attr_for_name} is already taken by #{names_by_serialized_attr[serialized_attr_for_name]}"
      end
      names_by_serialized_attr[serialized_attr_for_name] = name

      super(name, options)
    end

    def deserialize(value)
      detect { |type| type.send(serialized_attr) == value.to_i }
    end

    def coerce(value)
      coerced = deserialize(value) if value.is_a?(Integer)
      coerced || super
    end
  end
end
