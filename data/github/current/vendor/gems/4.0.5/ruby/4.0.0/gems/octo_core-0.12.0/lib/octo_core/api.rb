# typed: strict
# frozen_string_literal: true

module OctoCore
  module Api
    autoload :ActiveModelErrorConverter, "octo_core/api/active_model_error_converter"
    autoload :ErrorHandling, "octo_core/api/error_handling"
    autoload :HmacFilter, "octo_core/api/hmac_filter"

    DOCS_BASE_URL = T.let("https://docs.github.com", String)
  end
end
