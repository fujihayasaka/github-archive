# typed: true
# frozen_string_literal: true

module Repos
  module Security
    class OverviewForNonCollaboratorsComponent < ApplicationComponent
      attr_reader :repository

      def initialize(repository:)
        @repository = repository
      end

      def show_pvr_button?
        return false if AdvisoryDB::Innersource.repo_authorized?(repo: repository)

        repository.security_policy.exists? &&
          AdvisoryDB::Pvd.authorized_repo?(repo: repository) &&
          (!logged_in? || AdvisoryDB::Pvd.authorized_user?(repo: repository, user: current_user, check_spammy: false))
      end
    end
  end
end
