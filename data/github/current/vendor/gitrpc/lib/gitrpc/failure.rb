# rubocop:disable Style/FrozenStringLiteralComment
require "gitrpc/error"

module GitRPC
  # GitRPC takes a conservative approach to remote exception handling. Any
  # non-GitRPC::Error exception raised from a GitRPC::Backend operation is
  # wrapped in the special GitRPC::Failure when raised on the client side.
  # The original exception is made available for debugging purposes but should
  # ideally not be relied on for flow control.
  #
  # Note that this only applies to exceptions that are not descended from
  # GitRPC::Error. All core exceptions raised within backend methods are raised
  # using their real exception class on the client side. Backend method
  # implementations should be designed to rescue any expected error states and
  # re-raise as a subclass of GitRPC::Error
  class Failure < GitRPC::Error
    attr_reader :original

    # Public: Create a new Failure for the given Exception object.
    #
    # original - The original exception raised from the Backend method.
    #
    def initialize(original)
      super "#{original.class}: #{original.message}", original
      set_backtrace original.backtrace if backtrace.nil?
    end

    # Public: Encode the original exception in a form suitable for
    # serialization. This is typically used to send failure objects over
    # the wire so that they may be recreated using the Failure.decode or
    # Failure.raise methods.
    #
    # Returns a four element array with the exception class name, message,
    # backtrace array, and supplemental information hash.
    def encode
      info = @original.respond_to?(:failbot_context) ? @original.failbot_context : {}
      [@original.class.to_s, @original.message, @original.backtrace, info]
    end

    # Public: Decode a previously encoded failure tuple.
    #
    # failure - A four element array with the exception class name, message,
    #           backtrace array, and supplemental information hash. This is
    #           usually obtained by calling Failure#encode.
    #
    # Returns the exception
    def self.decode(failure)
      class_name, message, backtrace, info = failure

      exception_class = load_exception_class(class_name)
      boom = allocate_exception_object(exception_class)
      boom.write_exception_attribute :message, message

      info ||= {}
      boom.write_exception_attribute :info, info
      boom.set_backtrace(backtrace) if backtrace
      info.each { |name, value| boom.write_exception_attribute name, value }
      boom
    end

    # Public: Raise a Failure for the given encoded failure tuple. This is used
    # on the client side after receiving an encoded failure response. It should
    # never be used on the server side or outside RPC decode handlers.
    #
    # failure - A four element array with the exception class name, message,
    #           backtrace array, and supplemental information hash. This is
    #           usually obtained by calling Failure#encode. Alternatively,
    #           this may be a normal Exception object in which case decoding is
    #           skipped.
    #
    # Returns never.
    # Raises a GitRPC::Failure or GitRPC::Error subclass for core errors.
    def self.wrap(failure)
      remote = failure.is_a?(Array)
      original = remote ? decode(failure) : failure

      boom = original.is_a?(GitRPC::Error) ? original : new(original)
      backtrace = original.backtrace || []
      backtrace += ["---- THE WIRE ----"] + caller if remote
      boom.set_backtrace backtrace
      boom
    end

    # Public: Wrap (as above) and raise an encoded exception tuple or a
    # raw exception.
    def self.raise(failure)
      Kernel.raise(wrap(failure))
    end

    # Internal: Allocate an object for the given exception class with running
    # the initialize method. A special write_exception_attribute is added to the
    # object to establish the exception message and other attributes in a
    # non-specific way.
    def self.allocate_exception_object(exception_class)
      boom = exception_class.allocate
      def boom.write_exception_attribute(name, value)
        instance_variable_set "@#{name}", value
        meta = (class<<self; self; end)
        meta.send :attr_reader, name
      end
      boom
    end

    # Internal: Attempt to load the class object for a given fully qualified
    # exception class name.
    #
    # class_name - The name of the exception class to attempt to load.
    #
    # Returns an Exception subclass. If the class cannot be resolved, the
    # Failure class is used instead.
    def self.load_exception_class(class_name)
      eval "::#{class_name}" # rubocop:disable Security/Eval
    rescue NameError
      self
    end
  end

  # Raised when there is an error from the backend on git spawn.
  #
  # Adds the command to the argument for debugging.
  class SpawnFailure < Failure
    attr_reader :argv

    def initialize(wrapped_error, argv)
      @argv = argv
      super wrapped_error
    end

    def failbot_context
      {
        "command" => argv.join(" ")
      }
    end
  end
end
