# typed: true
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class RepositoriesMenuComponent < ApplicationComponent
      # tier - a SponsorsTier.
      def initialize(tier:)
        @tier = tier
      end

      private

      attr_reader :tier
      delegate :sponsorable, to: :tier

      def render?
        logged_in? && GitHub.sponsors_enabled?
      end

      def prompt
        repo = tier.repository
        return "None" unless repo

        if repo.readable_by?(current_user)
          repo.name_with_display_owner
        else
          "Private repository"
        end
      end

      def repository_errors
        tier.sponsors_only_repository_errors
      end

      def expand_input?
        tier.repository.present? || repository_errors.any?
      end

      memoize def repositories
        if sponsorable.organization?
          reject_repos_that_disallow_outside_collaborators(sponsorable.private_repositories)
        else
          # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          adminable_repo_ids = sponsorable.associated_repository_ids(min_action: :admin)
          # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          repos = Repository.private_scope.org_owned.active.where(id: adminable_repo_ids)
          reject_repos_that_disallow_outside_collaborators(repos)
        end
      end

      def owner_help_text
        if sponsorable.organization?
          sponsorable.display_login
        else
          "an organization that you administer"
        end
      end

      def show_seat_limit_warning?
        maintainer_has_seat_limit? || repo_owner_has_seat_limit?
      end

      # Private: Is the maintainer on a plan where they pay per collaborator?
      #
      # True if the sponsorable is an organization on a billing plan that is
      # billed per seat
      #
      # Returns Boolean
      def maintainer_has_seat_limit?
        sponsorable.organization? && sponsorable.plan.per_seat?
      end

      # Private: Are any repositories owned by an Organization on a billing
      # plan that charges per collaborator?
      #
      # User sponsorables may have access to private repositories that
      # are owned by Organizations that are billed per seat
      #
      # Returns Boolean
      def repo_owner_has_seat_limit?
        GitHub::PrefillAssociations.prefill_batch_method(repositories, :owner_on_per_seat_plan?)
        repositories.any?(&:owner_on_per_seat_plan?)
      end

      # Private: If the owner of a Repository is #enterprise_managed_user_enabled?, the
      # Repository cannot add outside collaborators. That means there is no way
      # to add sponsors to the Repository. If that is the case, we remove them
      # from the array.
      #
      # Returns: Array of Repository records that can add outside collaborators.
      def reject_repos_that_disallow_outside_collaborators(repos)
        GitHub::PrefillAssociations.prefill_batch_method(repos, :async_owner)
        GitHub::PrefillAssociations.prefill_batch_method(repos, :async_is_owner_enterprise_managed_organization?)

        repos.reject do |repo|
          repo.async_owner.sync.nil? || repo.async_is_owner_enterprise_managed_organization?.sync
        end
      end
    end
  end
end
