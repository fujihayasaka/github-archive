# typed: true
# frozen_string_literal: true

module NetworkHelper
  extend T::Helpers
  requires_ancestor { NetworkController }  # rubocop:disable GitHub/PreventViewHelpersInControllers

  # Public: draw a network tree.
  #
  # root       - the root Repository of the repo network
  # repo_map   - a Hash of repository network children, indexed by parent id
  # indent:    - the indentation level. Defaults to -1
  # draw_root: - whether or not to draw the root. true by default.
  # out:       - the output buffer. Defaults to a new ActiveSupport::SafeBuffer
  # use_icons: - whether or not to use person/org icons in place of gravatars.
  #              The default false value is intended for user-facing pages.
  #
  # Returns an ActiveSupport::SafeBuffer with a rendered repo tree.
  def draw_network_tree(root, repo_map, indent: -1, draw_root: true, out: ActiveSupport::SafeBuffer.new, use_icons: false, stafftools: false)
    out << draw_repository(root, use_icons: use_icons, stafftools: stafftools) if draw_root

    repos = sort_repos(root, repo_map)

    repos.each do |repo|
      tree_icon = repo == repos.last ? "l" : "t"
      out << draw_repository(repo, tree_icon: tree_icon, indent: indent + 1, use_icons: use_icons, stafftools: stafftools)
      draw_network_tree(repo, repo_map, indent: indent + 1, draw_root: false, out: out, use_icons: use_icons, stafftools: stafftools)
    end

    out
  end

  # Internal: sort repositories by owner name. Take into consideration repos withoutowners
  # root       - the root Repository of the repo network
  # repo_map   - a Hash of repository network children, indexed by parent id
  def sort_repos(root, repo_map)
    repos = Array(repo_map[root.id])
    orphaned_repos, valid_repos = repos.partition { |repo| repo.owner.nil? }
    valid_repos = valid_repos.sort_by { |repo| repo.owner.name.downcase }

    valid_repos + orphaned_repos
  end

  # Internal: render a repository node in a network tree.
  #
  # repo       - the Repository to draw.
  # tree_icon  - a String, 'l' or 't', describing the the graph T or L shape to
  #              draw on the left hand side of this node. Defaults to nil for
  #              no shape.
  # indent:    - optional indentation amount for this node. Defaults to 0.
  # use_icons: - whether or not to use person/org icons in place of gravatars
  #              as the tree icon for each node. Defaults to false.
  #
  # Returns a rendered partial.
  def draw_repository(repo, tree_icon: nil, indent: 0, use_icons: false, stafftools: false)
    if stafftools
      render partial: "stafftools/networks/repository", locals: {
        repo: repo,
        tree_icon: tree_icon,
        indent: indent,
        use_icons: use_icons,
      }
    else
      render partial: "network/repository", locals: {
        repo: repo,
        tree_icon: tree_icon,
        indent: indent,
        use_icons: use_icons,
      }
    end
  end

  sig { returns(T::Boolean) }
  def has_enforced_security_configuration_for_dependency_graph?
    repository_security_configuration = RepositorySecurityConfiguration.find_by(repository: current_repository)
    return false unless repository_security_configuration
    return false unless repository_security_configuration.enforced?

    !repository_security_configuration.feature_not_set?(:dependency_graph)
  end
end
