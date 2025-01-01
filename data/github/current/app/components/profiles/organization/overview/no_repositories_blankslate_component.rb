# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    module Overview
      class NoRepositoriesBlankslateComponent < ApplicationComponent
        attr_reader :organization, :is_member, :can_create_repository

        def initialize(organization:, is_member:, can_create_repository:)
          @organization = organization
          @is_member = is_member
          @can_create_repository = can_create_repository
        end

        private

        def icon
          return "repo" if is_member
          "repo-template"
        end

        def heading_copy
          return "Create your first #{organization.safe_profile_name} repository." if can_create_repository
          return "Your teams don't have access to any repositories." if is_member
          "This organization has no public repositories."
        end
      end
    end
  end
end
