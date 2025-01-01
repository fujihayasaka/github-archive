# typed: true
# frozen_string_literal: true

module Repositories
  class DemoNotificationComponent < ApplicationComponent
    attr_reader :organization, :repository

    def initialize(repository)
      @repository = repository
      @organization = @repository&.organization
    end

    def render?
      organization.present? && organization.adminable_by?(current_user) &&
        demo_repo? &&
        helpers.display_organization_notice?(organization, current_user, :demo_repository_notification, for_whole_org: true)
    end

    private

    def demo_repo?
      repository.created_for_demo_by_gh? || OrganizationOnboard::DemoRepository.where(repository:).exists?
    end
  end
end
