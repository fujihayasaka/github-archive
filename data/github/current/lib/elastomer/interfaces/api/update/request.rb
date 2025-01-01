# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Update
        module Request
          autoload :Body, "elastomer/interfaces/api/update/request/body"
          autoload :Params, "elastomer/interfaces/api/update/request/params"
        end
      end
    end
  end
end
