# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Delete
        autoload :Request, "elastomer/interfaces/api/delete/request"
        autoload :Response, "elastomer/interfaces/api/delete/response"
      end
    end
  end
end
