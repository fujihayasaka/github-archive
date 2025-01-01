# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class UserNamespaceRepository < Connections::Base
      description "A list of repositories owned by users in an enterprise with Enterprise Managed Users."

      total_count_field
    end
  end
end
