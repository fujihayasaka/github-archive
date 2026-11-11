# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrderDirection < Platform::Enums::Base
      description "Possible directions in which to order a list of items when provided an `orderBy` argument."

      value "ASC", "Specifies an ascending order for a given `orderBy` argument."
      value "DESC", "Specifies a descending order for a given `orderBy` argument."
    end
  end
end
