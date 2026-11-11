# frozen_string_literal: true

module GitHubTrilogyAdapter
  module QueryRetries
    # Allow retries in more places than upstream if query_retries is > 0
    def initialize(...)
      super
      @query_retries = @config[:query_retries] || 0
    end

    # Should match upstream except for `allow_retry`
    if defined? ActiveRecord::ConnectionAdapters::QueryIntent
      if ActiveRecord::ConnectionAdapters::AbstractAdapter.instance_methods.include? :execute_intent
        def execute_intent(intent)
          intent.instance_variable_set(:@allow_retry, @query_retries > 0)
          super(intent)
        end
      else
        def raw_execute(intent)
          intent.instance_variable_set(:@allow_retry, @query_retries > 0)
          super(intent)
        end
      end
    else
      def raw_execute(*args, **kwargs)
        super(*args, **kwargs.merge(allow_retry: @query_retries > 0))
      end
    end
  end
end
