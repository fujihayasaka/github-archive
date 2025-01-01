# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        autoload :Request, "elastomer/interfaces/api/search/request"
        autoload :Response, "elastomer/interfaces/api/search/response"
      end
    end
  end
end
