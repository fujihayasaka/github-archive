# typed: true
# frozen_string_literal: true

module Team::MemexDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig
  requires_ancestor { Team }

  include MemexProject::SharedMemexProjectsDependency

  included do
    T.bind(self, T.class_of(Team))

    # Public: Check if this team can be added to a Memex project board.
    #
    # memex_owner - the User or Organization who owns the Memex project board
    # viewer - the currently authenticated User
    #
    # Examples:
    #
    #   # To prevent N+1s when this method is called on a list of Team records, prefill it this way:
    #
    #   # Execute few queries to preload, such as in a controller action:
    #   GitHub::PrefillAssociations.prefill_batch_method(teams, :can_be_added_to_memex_project?, {
    #     memex_owner: this_organization,
    #     viewer: current_user,
    #   })
    #
    #   teams.each do |team|
    #     # Methods are preloaded and memoized - no queries are executed here!
    #     team.can_be_added_to_memex_project?(memex_owner: this_organization, viewer: current_user)
    #   end
    #
    # Returns a Boolean.
    batch_method :can_be_added_to_memex_project? do |*args|
      teams = args.shift
      options = args.shift || {}
      memex_owner = options[:memex_owner]
      viewer = options[:viewer]

      next Hash.new(false) unless memex_owner&.organization?

      promises = teams.map do |team|
        if team.organization_id == memex_owner.id
          # For secret teams, users must be able to read the team before being able to add or remove it from a
          # project.
          team.async_permit?(viewer, :read)
        else
          Promise.resolve(false)
        end
      end
      results = Promise.all(promises).sync

      teams.zip(results).to_h
    end
  end

  def memex_reviewer_hash
    {
      avatarUrl: primary_avatar_url(40),
      id: id,
      url: permalink,
      name: name,
      type: self.class.to_s,
    }
  end

  def accessible_memexes_scope(scope, viewer, min_permission_level = "read", filter_ids: [])
    async_accessible_memexes_scope(scope, viewer, min_permission_level, filter_ids:).sync
  end

  def async_accessible_memexes_scope(scope, viewer, min_permission_level = "read", filter_ids: [])
    self.async_organization.then do |owner|
      owner.accessible_memexes_scope(
        scope,
        viewer,
        min_permission_level,
        filter_ids:
      )
    end
  end

end
