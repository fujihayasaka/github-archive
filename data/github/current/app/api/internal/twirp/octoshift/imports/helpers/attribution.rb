# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module Attribution
        include ModelDelay

        def user_or_ghost(login)
          if login.present?
            find_mannequin_or_user_by_login(login)
          else
            User.ghost
          end
        end

        # Tries to find a mannequin or user associated with the login.
        # This helper method was added because in Proxima unlike mannequins,
        # user logins include the business shortcode suffix so looking up a mannequin through the
        # User model will return nil because the business shortcode will get appended to the login.
        # Therefore the lookup has to be done through the Mannequin model so the shortcode won't get appended to the login.
        def find_mannequin_or_user_by_login(login)
          replica(Mannequin).find_by(login:) || replica(User).find_by(login:)
        end

        def find_mannequin_or_user_by_login!(login)
          replica(Mannequin).find_by(login:) || replica(User).find_by!(login:)
        end

        # Just like `find_mannequin_or_user_by_login`, this helper method was added to address the same issue.
        # It will first try to lookup the logins through the Mannequin model and then through the User model if
        # there are any not found logins.
        def build_user_map(enumerable_object, login_attribute = nil, additional_fields = nil)
          return {} if enumerable_object.blank?

          base_fields = [:id, :login, :display_login]
          additional_fields ||= []
          select_fields = (base_fields | additional_fields)

          logins = login_attribute.nil? ? enumerable_object : enumerable_object.map(&login_attribute.to_sym)

          mannequin_map = replica(Mannequin).query do |klass|
            klass.where(login: logins).select(*select_fields).to_h { |mannequin| [mannequin.login, mannequin] }
          end

          not_found_logins = logins - mannequin_map.keys
          return mannequin_map if not_found_logins.blank?

          user_map = replica(User).query do |klass|
            # We need to use `display_login` here because we return it in `FetchOwnerMannequins`
            klass.where(login: not_found_logins).select(*select_fields).to_h { |user| [user.display_login, user] }
          end

          mannequin_map.merge(user_map)
        end
      end
    end
  end
end
