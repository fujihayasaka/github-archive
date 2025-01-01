# typed: true
# frozen_string_literal: true

module GitHub
  module Exceptions
    autoload :BasicRollup, "github/exceptions/basic_rollup"
    autoload :ActiveRecordRollup, "github/exceptions/active_record_rollup"
    autoload :CauseCatalogServiceFinder, "github/exceptions/cause_catalog_service_finder"
  end
end
