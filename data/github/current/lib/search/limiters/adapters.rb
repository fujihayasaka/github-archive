# typed: true
# frozen_string_literal: true

module Search
  module Limiters
    # These adapters are case-specific and used to add a rate limiting flow for their particular context.
    # If you add a new adapter, you must add it here in order for other modules to be able to find it.
    module Adapters
      autoload :CodesearchControllerAdapter, "search/limiters/adapters/codesearch_controller_adapter"
      autoload :SearchApiAdapter, "search/limiters/adapters/search_api_adapter"
    end
  end
end
