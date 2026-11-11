# typed: true
# frozen_string_literal: true

class Issue::Loader::ReactionGroups < Issue::Loader::Base
  def initialize(context, reaction_groups: [])
    @context = context
    @reaction_groups = reaction_groups
  end

  def self.load_for(context, reaction_groups: [])
    super new(context, reaction_groups: reaction_groups)
  end

  def load
    # load reaction group user ids
    reacting_user_ids_promises = @reaction_groups.map do |group|
      if group.total_count == 0
        group.preload_attr(:user_ids, [])
      else
        Platform::Loaders::ReactingUserIds.load(group.subject, group.content).then do |user_ids|
          group.preload_attr(:user_ids, user_ids)
        end
      end
    end

    viewer_can_react_promises = @reaction_groups.map do |group|
      has_reacted_promise = @context.viewer.nil? || group.total_count == 0 ? Promise.resolve(false) : Platform::Loaders::HasReacted.load(@context.viewer.id, group)
      has_reacted_promise.then do |has_reacted|
        group.preload_attr(:has_reacted, has_reacted)
      end
    end

    Promise.all(reacting_user_ids_promises + viewer_can_react_promises).sync
    @reaction_groups
  end
end
