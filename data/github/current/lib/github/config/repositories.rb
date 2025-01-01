# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Repositories
      def public_repositories_available?
        true
      end
    end
  end

  extend Config::Repositories
end
