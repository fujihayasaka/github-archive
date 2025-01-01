# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module DeleteByQuery
        module Request
          autoload :Body, "elastomer/interfaces/api/delete_by_query/request/body"
          autoload :Params, "elastomer/interfaces/api/delete_by_query/request/params"
        end
      end
    end
  end
end
