# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseMember < Edges::Base
      node_type Unions::EnterpriseMember
      description "A User who is a member of an enterprise through one or more organizations."
    end
  end
end
