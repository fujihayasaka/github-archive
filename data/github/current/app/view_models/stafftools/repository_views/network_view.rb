# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class NetworkView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::Sentry

      attr_reader :repository

      def page_title
        "#{repository.name_with_owner} - Network"
      end

      def is_root?
        repository.network_root?
      end

      def root
        repository.root
      end

      def rooting_violates_repo_limit?
        repository.private? && root.private? && repository.owner.at_private_repo_limit?
      end

      def has_forks?
        !(repo_map.size == 1 || repo_map[nil].blank?)
      end

      def network
        repository.network
      end

      def has_parent_network?
        repository.network.parent.present?
      end

      def parent_network
        repository.network.parent
      end

      def child_network_maps
        network.children.map do |child|
          repo_map = child.full_network_tree
          [repo_map[nil].first, repo_map]
        end
      end

      def has_child_networks?
        network.children.present?
      end

      def has_related_networks?
        network.family_ids.length > 1
      end

      def attachable_repos
        RepositoryNetwork.family_root_repositories(network).where.not(id: network.root.id)
      end

      def first
        repo_map[nil].first
      end

      def family_network_maps
        @family_network_map ||= repository.network.family_network_trees
      end

      def repo_map
        @repo_map ||= repository.network.full_network_tree
      end

      def allow_extract?
        return unless repository.online?
        repository.enough_space_to_extract?
      end

      def allow_detach?
        return unless repository.online?
        repository.enough_space_to_extract?
      end

      def allow_attach?
        has_related_networks?
      end

      def attach_button_text
        "Attach"
      end

      def attach_header_text
        "Attach to related network"
      end

      def attach_description_text
        allow_attach? ? "Attach this repository and its whole fork network to a related network." : "This repository has no related networks."
      end

      def root_repository_sentry_link
        sentry_query_link([Stafftools::Sentry::DOTCOM_PROJECT_ID], "job:ChangeNetworkRoot")
      end

      def is_in_org_owned_private_network_with_forks?
        repository.network&.org_owned_private_network_with_forks?
      end

      private

      def parent_network_link
        helpers.link_to(parent_network.root.name_with_owner, urls.gh_stafftools_repository_path(parent_network.root))
      end
    end
  end
end
