# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      autoload :Bulk, "elastomer/interfaces/api/bulk"
      autoload :Delete, "elastomer/interfaces/api/delete"
      autoload :Search, "elastomer/interfaces/api/search"
      autoload :Update, "elastomer/interfaces/api/update"
      autoload :UpdateByQuery, "elastomer/interfaces/api/update_by_query"
      autoload :Request, "elastomer/interfaces/api/request"
      autoload :Response, "elastomer/interfaces/api/response"
    end
  end
end
