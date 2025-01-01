# typed: true
# frozen_string_literal: true

# Public: A mixin to use on an ActiveRecord model that both:
#   1. can have Reactions attached to it
#   2. belongs to a Team
module Reaction::Subject::TeamContext
  extend ActiveSupport::Concern
  include Reaction::Subject

  def reaction_admin
    T.unsafe(self).team.organization
  end

  def async_reaction_admin
    T.unsafe(self).async_team.then(&:async_organization)
  end

  def reaction_path
    async_reaction_path.sync
  end

  def async_reaction_path
    T.unsafe(self).async_team.then do |team|
      team.async_organization.then do |org|
        UrlHelpers.update_team_reaction_path(org, team)
      end
    end
  end
end
