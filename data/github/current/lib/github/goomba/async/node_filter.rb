# typed: false
# frozen_string_literal: true

module GitHub::Goomba
  class Async::NodeFilter < NodeFilter
    attr_reader  :nodes

    def initialize(*args)
      super
      @nodes = []
    end

    def add_node(node)
      @nodes << node
    end

    # This shim allows WarpPipe pipelines to call this async filters with similar
    # mechanics to the non-async node filter's scan(document) method.  This bridge
    # allows the async filters to run from both WarpPipe and GitHubReferenceFilter,
    # with the intention to eventually remove GitHubReferenceFilter entirely.
    # Once GitHubReferenceFilter is removed, this method can be renamed
    # async_scan(document) to be naming-consistent with scan(document)
    #
    # See https://github.com/github/heart-services/issues/1036 for tracking on this work.
    def async_scan_doc(document)
      document.select(selector).each { |node| add_node(node) }
      async_scan
    end

    def async_scan
      raise NotImplementedError
    end

    def async_find_repository(owner_or_nwo)
      case owner_or_nwo
      when nil
        Promise.resolve(repository)
      when /\//
        owner, name = owner_or_nwo.split("/")

        async_repo_from_nwo = Platform::Loaders::ActiveRecord
          .load(::User, owner, column: :login, case_sensitive: false)
          .then do |user|
            next nil unless user
            Platform::Loaders::RepositoryByName.load(user.id, name)
          end

        async_repo_from_owner_id_repo_id = async_repo_from_nwo.then do |repo|
          next repo if repo
          next nil unless owner_or_nwo =~ /\A\d+\/\d+\z/
          Platform::Loaders::RepositoryById.load(owner.to_i, name.to_i)
        end

        async_repo_from_owner_id_repo_id.then do |repo|
          next repo if repo
          Platform::Loaders::RedirectedRepositoryByNwo.load(owner_or_nwo)
        end
      else
        if repository
          Platform::Loaders::ActiveRecord.load(::User, owner_or_nwo, column: :login, case_sensitive: false).then do |user|
            if user
              Platform::Loaders::RepositoryByOwnerId.load(repository.network_id, user.id)
            else
              Platform::Loaders::RedirectedRepositoryByOldOwner.load(repository.network_id, owner_or_nwo)
            end
          end
        else
          Promise.resolve(nil)
        end
      end
    end

    def async_can_access_repo?(repo)
      if repo.nil?
        Promise.resolve(false)
      elsif repo == entity
        Promise.resolve(true)
      else
        repo.async_readable_by?(current_user)
      end
    end

    # For integrations (bot users) we need to load the integration installation for the repository to determine
    # whether or not the team is visible.
    def async_load_installation(repo)
      if repo && current_user&.bot?
        current_user.async_load_installation_for(repo)
      else
        Promise.resolve(nil)
      end
    end

    def current_user
      return context[:viewer] if context[:viewer].present?

      context[:current_user]
    end
  end
end
