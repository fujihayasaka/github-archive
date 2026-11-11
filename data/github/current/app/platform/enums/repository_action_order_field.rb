# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryActionOrderField < Platform::Enums::Base
      description "Properties by which repository action connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order actions by creation time", value: "created_at"
      value "UPDATED_AT", "Order actions by update time", value: "updated_at"
      value "NAME", "Order actions by name", value: "name"
      value "RANK", "Order actions by rank", value: "rank_multiplier"
    end
  end
end
