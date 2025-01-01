# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Response
        autoload :Shards, "elastomer/interfaces/api/response/shards"
        autoload :FailureCause, "elastomer/interfaces/api/response/failure_cause"
      end
    end
  end
end
