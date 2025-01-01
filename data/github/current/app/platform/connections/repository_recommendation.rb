# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/EnsureConsistentConnections

module Platform
  module Connections
    class RepositoryRecommendation < Connections::Base
      # TODO before going public:
      # Should this connection have `total_count_field`?
      #
      # Since it doesn't have that field, it's explicitly
      # safelisted for different authz tests in
      # `test/test_helpers/platform/interface_helpers.rb`.
      mobile_only true
    end
  end
end
