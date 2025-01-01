# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DependencyGraphEcosystem < Platform::Enums::Base
      visibility :public

      description "The possible ecosystems of a dependency graph package."

      ::AdvisoryDB::Ecosystems.dependency_graph_supported.each do |ecosystem|
        value ecosystem.name.upcase, ecosystem.description, value: ecosystem.name.downcase
      end
    end
  end
end
