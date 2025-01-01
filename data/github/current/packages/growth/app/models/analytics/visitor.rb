# typed: true
# frozen_string_literal: true

module Analytics
  class Visitor
    # Public: Find a visitor by parsing the serialized string representation of
    # an Octolytics ID.
    #
    # octolytics_id - A String Octolytics ID
    #
    # Returns an Analytics::Visitor instance or `nil` if the `octolytics_id` is
    # missing or unparsable.
    def self.with_octolytics_id(octolytics_id)
      return unless octolytics_id&.valid_encoding?
      return unless octolytics_id.present?

      new OctolyticsId.coerce(octolytics_id)
    rescue OctolyticsId::CoercionError
      GitHub.dogstats.increment("octolytics_id.coercion_error")
      nil
    end

    # Public: Find a visitor by parsing the serialized integer representation
    # of an Octolytics ID.
    #
    # integer_id - An Integer Octolytics ID
    #
    # Returns an Analytics::Visitor instance or `nil` if the `integer_id` is
    # missing or unparsable.
    def self.find(integer_id)
      return unless integer_id.present?

      new OctolyticsId.coerce(integer_id)
    rescue OctolyticsId::CoercionError
      GitHub.dogstats.increment("octolytics_id.coercion_error")
      nil
    end

    # Public: Generate a new visitor with a fresh Octolytics ID.
    #
    # Returns an Analytics::Visitor instance.
    def self.create
      new OctolyticsId.generate
    end

    def initialize(id)
      @id = id
    end

    def ==(other)
      other.is_a?(self.class) && id == other.id
    end
    alias eql? ==

    # Public: Return the serialized integer representation of the visitor's
    # Octolytics ID
    #
    # Returns an Integer.
    def id
      @id.to_i
    end

    # Public: Return the serialized string representation of the visitor's
    # Octolytics ID
    #
    # Returns a String.
    def octolytics_id
      @id.to_s
    end

    # Public: Return the serialized string representation of the visitor's
    # Octolytics ID without a version prefix
    #
    # Returns a String.
    def unversioned_octolytics_id
      @id.unversioned
    end

    # Public: Return `false` to mimic a User object's `spammy?` methodkj
    #
    # Returns a Boolean
    def spammy?
      false
    end
  end
end
