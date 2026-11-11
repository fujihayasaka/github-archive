# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class OrganizationWideProjectsV2Role < Resolvers::Base
      def resolve
        object.projects_base_role
      end
    end
  end
end
