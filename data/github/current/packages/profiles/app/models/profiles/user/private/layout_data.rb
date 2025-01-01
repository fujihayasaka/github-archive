# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Private
      class LayoutData < BaseLayoutData
        memoize def repository_count
          measure(metric: "public_repository_count", type: :count) { metadata.repository_count }
        end

        memoize def show_follow_button?
          profile_user.followed_by?(viewer)
        end
      end
    end
  end
end
