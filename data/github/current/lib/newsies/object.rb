# typed: true
# frozen_string_literal: true

module Newsies
  # Newsies objects are conceptually designed as interfaces to convert
  # a GitHub-specific model, like an Issue, over to a more abstract
  # Newsies "object" like a Thread.
  #
  # For the most part, there isn't any business logic or requirements
  # in these objects; they primarily serve as utility or wrapper classes
  # that do things like string conversion and key serialization.
  class Object
    include GitHub::VexiActor
    class InvalidKey < ::Newsies::Error
      def initialize(key, key_separator)
        super "key invalid (must be 'Type#{key_separator}id')"
      end
    end

    # Internal: The string used to separate items (like list id, thread type and
    # thread id) in thread keys.
    #
    # Examples:
    #   Issue;3232 (thread type and thread id)
    #   23;Issue;3232 (list id, thread type, and thread id)
    KEY_SEPARATOR = ";"

    # Public: Ensures that provided objects are Newsies::Objects.
    #
    # objects - An Array of Newsies::Objects or objects to convert to a Newsies::Object.
    #
    # Returns an Array of Newsies::Object instances.
    def self.to_objects(objects)
      objects.map { |object| to_object(object) }
    end

    # Public: Ensures that provided instance is a Newsies::Object.
    #
    # object - The Newsies::Object or object to convert to a Newsies::Object.
    #
    # Returns a Newsies::Object instance.
    def self.to_object(object)
      return object if object.is_a?(self)
      new(to_type(object), to_id(object))
    end

    # Public: Converts a class to a string representation of the newsies type.
    #
    # klass - The class to convert to String type.
    #
    # Returns String.
    def self.type_from_class(klass)
      raise RuntimeError, "`klass` must be a class" unless klass.is_a?(Class)
      return "Grit::Commit" if klass.name == "Commit"
      klass.name
    end

    # Public: Converts an object to a string representation of the object type.
    #
    # object - The object to convert to String type.
    #
    # Returns String.
    def self.to_type(object)
      return object.type if object.is_a?(self)
      type_from_class(object.class)
    end

    # Public: Converts an object to a representation of the object id.
    #
    # object - The object to convert to id.
    #
    # Returns String or Integer id.
    def self.to_id(object)
      return object.oid if object.respond_to?(:oid)
      object.id
    end

    # Public: Converts a key into a Newsies::Object instance.
    #
    # key - The String representation of type and id.
    #
    # Returns Newsies::Object instance.
    def self.from_key(key, separator: KEY_SEPARATOR)
      raise InvalidKey.new(key, separator) unless valid_key?(key, separator: separator)

      type, id = key.split(separator, 2)
      new(type, id)
    end

    # Public: Converts a object to a key.
    #
    # object - The object to convert.
    #
    # Returns the String representation of type and id.
    def self.to_key(object, separator: KEY_SEPARATOR)
      to_object(object).key(separator)
    end

    # Public: Is the provided key valid.
    #
    # key - The String key.
    # separator - An Optional String separator that the key parts are
    #             joined with.
    #
    # Returns true if valid else false.
    def self.valid_key?(key, separator: KEY_SEPARATOR)
      key && key.size >= 3 && key.include?(separator)
    end

    attr_reader :type
    attr_reader :id

    def initialize(type, id)
      raise ArgumentError, "type cannot be blank" if type.blank?
      raise ArgumentError, "id cannot be blank" if id.blank?

      @type = type
      @id = id
    end

    def key(separator = KEY_SEPARATOR)
      "#{@type}#{separator}#{@id}"
    end

    def eql?(other)
      self.class.eql?(other.class) && @type == other.type && @id == other.id
    end
    alias_method :==, :eql?

    def hash
      [self.class, @type, @id].hash
    end

    def flipper_id
      "#{@type}:#{@id}"
    end

    def vexi_id
      flipper_id
    end
  end
end
