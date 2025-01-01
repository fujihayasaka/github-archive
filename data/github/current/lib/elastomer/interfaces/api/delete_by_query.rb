# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module DeleteByQuery
        autoload :Request, "elastomer/interfaces/api/delete_by_query/request"
        autoload :Response, "elastomer/interfaces/api/delete_by_query/response"
      end
    end
  end
end
