# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # HTML filter that replaces @user mentions with links. Mentions within <pre>,
  # <code>, and <a> elements are ignored. Mentions that reference users that do
  # not exist are ignored.
  #
  # Context options:
  #   :base_url - Used to construct links to user profile pages for each
  #               mention.
  #
  # The following keys are written to the result hash:
  #   :mentioned_users - An array of User objects that were mentioned.
  #
  class MentionFilter < ::HTML::Pipeline::MentionFilter
    # about @mentions instead of triggering a real mention.
    MentionLogins = %w(
      mention
      mentions
      mentioned
      mentioning
    )

    # Pattern used to extract @mentions from text works with emu users
    # to debug https://rubular.com/r/i6kImuNXzO242D
    MentionPattern = /
      (?:^|[^a-zA-Z0-9_`])                                       # beginning of string or non-word, non-` char
      @((?>[a-z0-9][a-z0-9-]*_[a-zA-Z0-9]+|[a-z0-9][a-z0-9-]*))  # @username and @username_emu for emu support
      (?!\/)                                                     # without a trailing slash
      (?=
        \.+[ \t\W]|                                              # dots followed by space or non-word character
        \.+$|                                                    # dots at end of line
        [^0-9a-zA-Z_.`]|                                         # non-word character except dot or `
        $                                                        # end of line
      )
    /ix

    # The number of @mentions allowed in an individual content post.
    MENTION_LIMIT = 50

    def self.cache_key(context)
      [
        "mention_limit=#{mention_limit(context)}",
        ("info_url=#{context[:info_url]}" if context[:info_url]),
        ("skip_hovercard" if context[:disable_hovercard_attributes])
      ].reject(&:blank?).join(":")
    end

    def self.mention_limit(context)
      context[:mention_limit] || MENTION_LIMIT
    end

    # Override parent implementation b/c https://github.com/jch/html-pipeline/pull/157
    # changed how usernames are looked up. This reverts it back to the old behavior
    def self.mentioned_logins_in(text, username_pattern = UsernamePattern)
      text.gsub MentionPattern do |match|
        login = $1
        yield match, login, MentionLogins.include?(login.downcase)
      end
    end

    def call
      mentioned_users.clear
      doc = super
      arrayify_mentioned_users
      doc
    end

    # List of User objects that were mentioned in the document. This is
    # available in the result hash as :mentioned_users.
    def mentioned_users
      result[:mentioned_users] ||= Hash.new
    end

    # Internal: turn the stored mentioned_users into an array for use
    # outside this class
    def arrayify_mentioned_users
      result[:mentioned_users] = mentioned_users.values.compact
    end

    def mention_limit
      @mention_limit ||= self.class.mention_limit(context)
    end

    # Internal: Should we prevent "mention spam" here?
    #
    # We only care in public spaces.
    # And this is also controlled at an installation-level switch
    #
    # Returns Boolean
    def prevent_mention_spam?
      return @prevent_spam if defined?(@prevent_spam)
      @prevent_spam = GitHub.prevent_mention_spam? && public?
    end

    # Internal: Is this happening in a public place?
    #
    # Delegate to the private state of the entity,
    # but act public if no entity is defined
    #
    # Returns Boolean
    def public?
      return true unless entity
      !entity.private?
    end

    # Override superclass method to check if the user exists and add spam
    # checking.
    def link_to_mentioned_user(login)
      cache = false
      if prevent_mention_spam?
        cache = mentioned_users.size >= mention_limit
      end

      if user = user_for(login, cache)
        result[:mentioned_usernames] |= [user.login]
        url = helpers.user_url(user)
        skip_hovercard = context[:disable_hovercard_attributes]
        helpers.profile_link(user, class: "user-mention", skip_hovercard: skip_hovercard, url: url) do
          "@#{user.display_login}"
        end
      else
        "@#{login}"
      end
    end

    # Internal: get a user for the given login
    # with caching the lookup to a hash
    #
    # login      - String login to look up
    # cache_only - Boolean indicating whether to skip querying the database
    #              (defaults to true)
    #
    # Returns a User or nil
    def user_for(login, cache_only = true)
      key = login.downcase

      current_user = context[:current_user]
      _, shortcode = current_user.try(:login).to_s.split("_", 2)

      # properly filter EMU users
      if current_user&.is_enterprise_managed?
        # EMU users can only mention other EMU users in the same enterprise
        return unless key.include?("_#{shortcode}")
      elsif current_user&.bot?
        if key.include?("_")
          # bot trying to mention an EMU user
          if business = repository&.owner&.business
            # if the mention happens in a repo owned by a business, check the mentioned user is in the same business
            return unless key.include?("_#{business.shortcode}")
          end
        end
      else
        # non-EMU users can only mention other non-EMU users
        return if key.include?("_")
      end

      user = if mentioned_users.include? key
        mentioned_users[key]
      elsif !cache_only
        User.find_by_login(login)
      end

      mentioned_users[key] = user
    end

    private

    def helpers
      return @view_context if defined?(@view_context)
      @view_context = EmptyController.new.view_context
    end
  end
end
