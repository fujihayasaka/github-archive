# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    autoload :AnonymousRequest, "github/middleware/anonymous_request"
    autoload :Constants, "github/middleware/constants"
    autoload :DatabaseSelection, "github/middleware/database_selection"
    autoload :Stats, "github/middleware/stats"
    autoload :UnknownHttpMethod, "github/middleware/unknown_http_method"
    autoload :TenantSelection, "github/middleware/tenant_selection"
  end
end
