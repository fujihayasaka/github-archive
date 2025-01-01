# typed: false
# frozen_string_literal: true

module GitHub
  module Authentication
    module UserHandler
      # Find or create a User.
      #
      # uid   - The login String of the user.
      # entry - Optional entry payload from external auth mechanism.
      #         Implementation specific.
      #
      # Returns a user and a nil message if a User was found or created.
      # Returns nil and a message if there was an error.
      def find_or_create_user(uid, entry = nil)
        user, message = find_user(uid, entry)

        if user.nil? && message.nil?
          user, message = create_user(uid, entry)
        end

        [user, message]
      end

      # Try finding a User.
      #
      # uid   - The login String of the user.
      # entry - Optional entry payload from external auth mechanism.
      #         Implementation specific.
      #
      # Returns a User and a nil message if the User was found.
      # Returns nothing if no user was found.
      # Returns nil and a message if there was an error.
      def find_user(uid, entry = nil)
        if uid["@"]
          user = User.find_by_email(uid)
        else
          login = User.standardize_login(uid)
          user = User.find_by_login(login)
        end
        return if user.nil?
        if user.user?
          [user, nil]
        else
          [nil, "Cannot authenticate as an Organization"]
        end
      end

      # Try creating a User.
      #
      # uid   - The login String of the user.
      # entry - Optional entry payload from external auth mechanism.
      #         Implementation specific.
      #
      # Returns a User if the User was created
      # Returns nil and a message if there was an error.
      def create_user(uid, entry = nil, site_admin = false, default_opts = {})
        if GitHub.enterprise?
          return nil, "GitHub Enterprise license is out of seats." if GitHub::Enterprise.license.reached_seat_limit?
          site_admin ||= GitHub.enterprise_first_run?
        end

        user = ActiveRecord::Base.connected_to(role: :writing) do
          User.create_with_random_password(uid, site_admin, default_opts)
        end

        if user.valid?
          GitHub::Authentication.logger.info("Created user", "code.namespace" => self.class.name, "code.function" => __method__, "gh.enduser.login" => user.login, "gh.auth.login" => uid)
          user
        else
          [nil, "Unable to create the user because #{user.errors.full_messages.to_sentence.downcase}"]
        end
      end
    end
  end
end
