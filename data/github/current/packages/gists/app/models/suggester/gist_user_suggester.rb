# typed: false
# frozen_string_literal: true

module Suggester
  class GistUserSuggester
    def initialize(viewer:, gist:)
      @viewer = viewer
      @gist = gist
    end

    def mentions
      to_hash = Suggester::UserSerializer.new(viewer: @viewer)
      users.map(&to_hash)
    end

    private

    def users
      list = []
      list.concat(@viewer.following_for_viewer(@viewer))
      list.concat(User.where(id: @gist.comments.pluck(:user_id)))
      list.concat([@gist.user]) unless @viewer.id == @gist.user_id

      list.concat(@viewer.organizations)
      list.concat(@viewer.billing_manager_organizations)

      filter = Suggester::BlockedUserFilter.new(viewer: @viewer)
      list = list.reject(&filter)

      GitHub::PrefillAssociations.prefill_associations(list, [:profile, { user_status: :organization }])
      list
    end
  end
end
