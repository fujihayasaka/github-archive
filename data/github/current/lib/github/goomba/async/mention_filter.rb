# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class MentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers
    SELECTOR = Goomba::Selector.new(match: "gh|user-mention")

    def self.cache_key(context)
      GitHub::HTML::MentionFilter.cache_key(context)
    end

    def initialize(*args)
      super
      @user_cache = {}
    end

    def selector
      SELECTOR
    end

    def mention_limit
      @mention_limit ||= context[:mention_limit] || GitHub::HTML::MentionFilter::MENTION_LIMIT
    end

    def async_scan
      logins = @nodes.map { |node| node["login"].downcase }.uniq
      if prevent_mention_spam?
        logins = logins[0, mention_limit]
      end

      # When there's a current tenant, we expect at-mentions to reference the display_login without
      # the tenant suffix.
      #
      # With no current tenant, we expect at-mentions to reference the login with the tenant suffix.
      if current_tenant = GitHub::CurrentTenant.get
        tenant_suffix = current_tenant.shortcode
        logins = logins.map { |login| User.standardize_login(login, suffix: tenant_suffix) }
      end

      Platform::Loaders::ActiveRecord.load_all(::User, logins, column: :login, case_sensitive: false).then do |users|
        users.each do |user|
          if user
            @user_cache[user.display_login.downcase] = user
          end
        end
      end.then do
        result[:mentioned_users] = @user_cache.values
        result[:mentioned_usernames] = @user_cache.keys
      end
    end

    def call(node)
      login = node["login"]
      user = @user_cache[login.downcase]
      return "@#{login}" if user.nil?

      url = helpers.user_url(user)

      user_reference_wrapper(login) do |wrapper|
        wrapper.authorized { helpers.profile_link(user, class: "user-mention notranslate", url: url) { "@#{user.display_login}" } }
        wrapper.unauthorized { "@#{login}" }
      end
    end

    private

    def helpers
      EmptyController.new.view_context
    end

    def prevent_mention_spam?
      return @prevent_spam if defined?(@prevent_spam)
      @prevent_spam = GitHub.prevent_mention_spam? && public?
    end

    def public?
      return true unless entity
      !entity.private?
    end
  end
end
