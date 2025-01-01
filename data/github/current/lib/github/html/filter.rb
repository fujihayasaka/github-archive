# typed: true
# frozen_string_literal: true

# GitHub::HTML::Filter is an alias for ::HTML::Pipeline::Filter
# We re-open it here to add additional methods, but use the original name
# to avoid a Sorbet "constant redefined" error.
module HTML
  class Pipeline
    class Filter
      include GitHub::IssueReferenceResolution
      # Public: The dynamic GitHub base URL based on the request
      #
      # Returns String.
      def base_url
        GitHub.urls.url
      end

      # Internal: part of filter initialization. Helps us enforce consistency.
      # See https://github.com/github/github/pull/15114
      def validate
        raise ArgumentError, "set :entity instead of :repository" if context.key?(:repository)
      end

      # Public: Returns the entity within the context, or nil.
      def entity
        context[:entity]
      end

      # Public: Returns the entity within the context if it's a Repository object.
      def repository
        entity if entity.is_a? Repository
      end

      # Public: Can the user access the entity?
      #
      # An entity can be accessed if it's readable by the user who
      # submitted the content of this filter, or if it's the same as the
      # entity context for the filter run.
      #
      # Returns Boolean, or raises if entity is unknown (not a Repository)
      def can_access_entity?(ent)
        case ent
        when nil
          false
        when Repository
          ent == entity || ent.readable_by?(current_user)
        else
          raise TypeError, "unexpected class #{ent.class}"
        end
      end

      # Public: Can the user access the repo?
      #
      # see can_access_entity? (above) for details
      #
      # Returns Boolean, or raises if entity is unknown (not a Repository)
      def can_access_repo?(repo)
        can_access_entity?(repo)
      end

      # Public: Find a Repository object given an object or string, falling back to the
      # current entity (from the context).
      #
      # @param [string | Repository] - A string reference or Repository object, or nil.
      #
      # If a name with owner String ("owner/name") is provided, look up the
      # Repository and return it.
      #
      # If a String (not a NWO, for example: "owner") is provided, look it up in
      # the repository's network.
      #
      # Returns a Repository object if found, or nil when no Repository could be
      # located.
      def find_repository(repo)
        find_repo(repo, repository)
      end

      # Public: Get entity text for a given nwo
      #
      # Will be blank if the nwo matches the current entity context
      # Will be the user name if the nwo matches an entity (repository) in the same network
      # Will be the full nwo otherwise
      #
      # nwo - name-with-owner of the entity
      #
      # Returns a String of the entity identification
      def entity_text(nwo)
        text = nwo

        if entity
          if entity.name_with_owner == nwo
            text = ""
          elsif repository && repository.in_network?(Repository.with_name_with_owner(nwo))
            text = nwo.split("/").first
          end
        end

        text
      end
      alias_method :repo_text, :entity_text

      # Internal: Exposes organization when passed in context.
      def organization
        context[:organization]
      end
    end
  end
end
