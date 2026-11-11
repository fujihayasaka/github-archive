# typed: true
# frozen_string_literal: true

# Represents zero or more errors occuring during provisioning

module Platform::Provisioning
  class Errors
    include Enumerable

    attr_reader :all

    # Public: Create a new list of provisioning errors
    #
    # errors  - one or more strings (representing an error message) or
    #           instances of Platform::Provisioning::Error
    #           Strings will be converted into an error representing
    #           Platform::Provisioning::Error::INTERNAL_ERROR, with the String as
    #           the message.
    #
    # Returns a Platform::Provisioning::Errors
    def initialize(errors)
      @all = Array.wrap(errors).map do |error|
        if !error.is_a?(Platform::Provisioning::Error)
          Platform::Provisioning::Error.internal_error(message: error)
        else
          error
        end
      end
    end

    # Public: An enumerable representing all provisioning errors.
    #
    # Returns an Enumerable, or yields each error to the given block
    def each(&block)
      return enum_for(:each) unless block_given?

      @all.each { |e| yield e }
    end

    # Public: Get an error for a specific reason
    #
    # Returns an Error or nothing
    def get(reason)
      return nil if @all.none?
      return @all.first if @all.size == 1
      errors = @all.select { |e| e.reason == reason }
      return nil if errors.none?
      errors.first
    end

    # Public: return a list of full error messages. Intended to behave like
    # ActiveModel::Errors#full_messages.
    #
    # Returns an Array of Strings
    def full_messages
      each.map { |e| e.message }
    end
  end
end
