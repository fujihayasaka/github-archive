# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Bulk
        module Response
          autoload :Body, "elastomer/interfaces/api/bulk/response/body"
          autoload :Error, "elastomer/interfaces/api/bulk/response/error"
          autoload :Item, "elastomer/interfaces/api/bulk/response/item"
          autoload :ItemResult, "elastomer/interfaces/api/bulk/response/item_result"
        end
      end
    end
  end
end
