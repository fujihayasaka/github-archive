# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class SendMultiple
    # See GitRPC.send_multiple.
    def self.send_multiple(urls, message, args, kwargs, options = {})
      new(urls, options).send_message(message, args, kwargs)
    end

    def initialize(urls, options)
      @urls = urls
      @options = options
    end

    attr_reader :urls, :options

    # Sends a message to all urls.
    #
    # Returns two hashes, one with answers and the other
    # with errors.
    def send_message(message, args, kwargs)
      answers, errors = {}, {}
      backends.each do |backend|
        backend_answers, backend_errors = backend.send_message(message, args, kwargs)
        answers.update(backend_answers)
        errors.update(backend_errors)
      end
      [answers, errors]
    end

    private

    # Resolve all URLs, and return an array of helper classes
    # that can do the actual send_message calls.
    def backends
      backend_helpers = Hash.new { |h, backend_class| h[backend_class] = build_backend_helper(backend_class) }
      urls.each do |url|
        backend = GitRPC::Protocol.resolve(url, options)
        backend_helpers[backend.class].add(url, backend)
      end
      backend_helpers.values
    end

    # Builds a helper for the given backend_class.
    #
    # The returned object will respond to the following methods:
    # - add(url, backend)
    # - send_message(message, args, kwargs)
    #
    def build_backend_helper(backend_class)
      backend_class.respond_to?(:send_multiple) ? SendInParallel.new(backend_class, options) : SendSerially.new
    end

    # For protocol classes that support parallel dispatch.
    class SendInParallel
      def initialize(backend_class, options)
        @backend_class = backend_class
        @options = options
      end

      attr_reader :backend_class, :options

      def add(url, backend)
        urls[backend] = url
      end

      # Delegate send_message to the protocol class.
      #
      # The backend operates in terms of GitRPC::Protocol objects.
      # So this method is responsible for converting the result hashes'
      # keys back to URLs.
      def send_message(message, args, kwargs)
        answers, errors = backend_class.send_multiple(urls.keys, message, args, kwargs, options)
        error_map = backend_class.respond_to?(:map_error) ? backend_class.method(:map_error) : lambda { |e| e }
        answers = Hash[answers.map { |backend, answer| [urls[backend], answer] }]
        errors = Hash[errors.map { |backend, error| [urls[backend], error_map[error]] }]
        [answers, errors]
      end

      private

      def urls
        @urls ||= {}
      end
    end

    # For protocol classes that do not support parallel dispatch.
    class SendSerially
      def add(url, backend)
        backends << [url, backend]
      end

      # Send the given message to each backend sequentially.
      def send_message(message, args, kwargs)
        answers, errors = {}, {}
        backends.each do |url, backend|
          begin
            answers[url] = backend.send_message(message, *args, **kwargs)
          rescue => e
            errors[url] = e
          end
        end
        [answers, errors]
      end

      private

      def backends
        @backends ||= []
      end
    end
  end
end
