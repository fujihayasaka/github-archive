# typed: true
# frozen_string_literal: true

module RepositoryAdvisories
  class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include Repos::AdvisoriesHelper
    attr_reader :current_repository, :page, :state

    def show_new_button?
      advisory_management_authorized? || pvd_authorized? || (current_user.nil? && pvd_repo_authorized?)
    end

    def advisory_management_authorized?
      return @advisory_management_authorized if defined? @advisory_management_authorized

      @advisory_management_authorized =
        current_repository.advisory_management_authorized_for?(current_user)
    end

    # In order to distinguish between a couple of different scenarios, we are allowing spammy users here because we
    # are explicitly checking it below before displaying the appropriate button
    def pvd_authorized?
      return @pvd_authorized if defined? @pvd_authorized

      @pvd_authorized = use_pvd_workflow?(check_spammy: false)
    end

    def pvd_repo_authorized?
      return @pvd_repo_authorized if defined? @pvd_repo_authorized

      @pvd_repo_authorized = AdvisoryDB::Pvd.authorized_repo?(repo: current_repository)
    end

    def description_text
      if show_new_button?
        if advisory_management_authorized?
          "Privately discuss, fix, and publish information about security vulnerabilities in your repository's code."
        else
          "View known security vulnerabilities and report new vulnerabilities privately to maintainers."
        end
      else
        "View information about security vulnerabilities from this repository's maintainers."
      end
    end
  end
end
