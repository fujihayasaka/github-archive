# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The UserFilter is used to limit search results to a particular user or
    # collection of users. This class encapsulates the logic of looking up
    # users and generating ElasticSearch term filters.
    class UserFilter < TermFilter

      attr_reader :current_user, :cap_filter

      # Create a new UserFilter.
      #
      # opts - The options Hash
      #   :field - the document field containing the user IDs
      #
      def initialize(opts = {})
        super(opts)

        @field ||= :user_id
        @current_user = opts[:current_user]
        @cap_filter = opts[:cap_filter]
        @exclude_private_profiles = opts.fetch(:exclude_private_profiles)

        map_bool_collection
      end

      # This reason can be used when the user filter is invalid.
      def invalid_reason
        "The listed users cannot be searched either because the users do not exist or you do not have permission to view the users."
      end

      # Internal: Take the boolean collection and convert all the values into
      # user IDs if possible.
      #
      # Returns this filter's boolean collection.
      def map_bool_collection
        return bool_collection if defined? @mapped
        @mapped = true

        # save these off for our validity check
        must_flag     = bool_collection.must?
        must_not_flag = bool_collection.must_not?

        # convert login strings to user IDs
        hash = display_logins
        bool_collection.map_all! do |display_login|
          display_login.is_a?(Symbol) ? display_login : hash[display_login.downcase]
        end

        bool_collection.uniq!

        # did we specify invalid user IDs?
        @valid = (must_flag     == bool_collection.must?) &&
                 (must_not_flag == bool_collection.must_not?)

        # prune `must_not` IDs from the `must` and `should` lists
        bool_collection.intersect!
        bool_collection
      end

      # Internal: Convert the `login` strings from the boolean collection into
      # user IDs. The logins will be downcased, and the returned hash will be
      # keyed by these downcased login strings.
      #
      # Returns a Hash mapping user logins to IDs.
      def display_logins
        display_logins = bool_collection.all
        return {} if display_logins.empty?

        user_logins = []
        app_slugs = []
        display_logins.each do |display_login|
          next if display_login.is_a?(Symbol)

          display_login = display_login.downcase

          # Convert `author:app/login` to `login[bot]` so we find Bot users in
          # the same query as other users.
          display_login.match(%r{\Aapp/(.+)}) do |m|
            app_slugs << m[1]
          end

          user_logins << display_login
        end

        ary = User.select("id, login").where(login: user_logins, spammy: false)

        ary = ary.where.not(id: protected_account_ids) if protected_account_ids.any?

        if invalidate_private_profile_searches?
          ary = ary.with_visible_profiles_for(current_user)
        end

        login_hash = ary.inject(Hash.new) do |hash, user|
          display_login = User.to_display_login(user.login).downcase
          hash[display_login.downcase] = user.id

          hash
        end

        return login_hash unless app_slugs.any?

        bots = Bot.with_slugs(app_slugs).select(:id, :login)

        bots.each do |bot|
          # adds the `app/` suffix to the bot slug
          display_login = Bot.query_filter_from_login(bot.slug)
          login_hash[display_login] = bot.id
        end

        login_hash
      end

      def invalidate_private_profile_searches?
        flag_enabled = FeatureFlag.vexi.enabled_or_raise?(:invalidate_private_profile_searches) || FeatureFlag.vexi.enabled_or_raise?(:invalidate_private_profile_searches, @current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        flag_enabled && @exclude_private_profiles
      end

      def protected_account_ids
        return @protected_account_ids if defined?(@protected_account_ids)

        @protected_account_ids = if cap_filter.present?
          if current_user&.is_enterprise_managed? && current_user.enterprise_managed_business&.idp_cap_for_web_enabled?
            cap_filter.unauthorized_resource_ids(
              current_user&.resources_for_cap_filter,
              only: [:ip_allowlist, :external_conditional_access_policy]
            )
          else
            cap_filter.unauthorized_resource_ids(
              current_user&.resources_for_cap_filter,
              only: :ip_allowlist
            )
          end
        else
          []
        end
      end
    end  # UserFilter
  end  # Filters
end  # Search
