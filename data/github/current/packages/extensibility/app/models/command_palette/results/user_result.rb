# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class UserResult < Result
      def self.type
        User
      end

      def self.create(user, priority, context, group = nil)
        # Small weight for your own user to get you above other users
        priority = priority + PRIORITY_WEIGHTS[:current_user] if user == context&.current_user
        title = "@#{user.display_login}"
        title += " - #{user.profile_name}" if user.profile_name.present?

        new(
          priority: priority,
          title: title,
          typeahead: user.display_login,
          scope: ResultScope.new(user),
          icon: Icons::Avatar.new(url: user.primary_avatar_url, alt: "@#{user.display_login}"),
          action: Actions::JumpToAction.new(path: user_path(user)),
          group: group || :users,
          object: user,
          match_fields: [user.display_login, user.profile_name].compact,
        )
      end
    end
  end
end
