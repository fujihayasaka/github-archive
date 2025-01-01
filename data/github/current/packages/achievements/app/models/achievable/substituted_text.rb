# typed: false
# frozen_string_literal: true

class Achievable
  class SubstitutedText
    SUBSTITUTION_PATTERN_RX = /(%{[^}]+})/

    def initialize(
      text,
      achievement:,
      current_user:,
      visible_models:,
      view_context: StringContext.new,
      locale: "en"
    )
      @text = text
      @achievement = achievement
      @current_user = current_user
      @visible_models = visible_models
      @view_context = view_context
      @locale = locale
    end

    def async_render
      if text =~ SUBSTITUTION_PATTERN_RX
        part_promises = []

        text.split(SUBSTITUTION_PATTERN_RX) do |chunk|
          substitution = SUBSTITUTIONS[chunk]
          if substitution
            if substitution[:needs_model]
              part_promises << achievement.async_unlocking_model.then do |model|
                visible = if model.respond_to?(:filter)
                  model = model.filter { |child_model| @visible_models.include?(child_model) }
                  true
                else
                  @visible_models.include?(model)
                end
                instance_exec(visible, model, &substitution[:block])
              end
            else
              part_promises << Promise.resolve(instance_eval(&substitution[:block]))
            end
          else
            part_promises << Promise.resolve(chunk)
          end
        end

        Promise.all(part_promises).then { |parts| safe_join(parts) }
      else
        Promise.resolve(text)
      end
    end

    def to_s
      async_render.sync
    end

    def self.needs_unlocking_model?(text)
      subs_with_model = SUBSTITUTIONS.select { |_name, info| info[:needs_model] }.map(&:first)
      text.match?(/#{subs_with_model.map { |sub| Regexp.escape(sub) }.join('|')}/)
    end

    private

    attr_reader :text, :current_user, :achievement

    delegate :safe_join, :content_tag, :link_to, :hovercard_data_attributes_for_user,
      :user_path, :repository_path,
      :to_sentence, :repository_limit,
      to: :@view_context, private: true

    # Substitution method registration machinery

    SUBSTITUTIONS = {}

    private_class_method def self.substitution(name, &block)
      needs_model = case block.arity
      when 0
        false
      when 2
        true
      else
        raise "Substitution #{name}'s block must accept either 0 or 2 arguments."
      end

      SUBSTITUTIONS["%{#{name}}"] = {
        needs_model: needs_model,
        block: block,
      }
    end

    # Helpers shared by substitution methods

    def tier
      achievement.achievable.tier(achievement.tier)
    end

    def render_user_mention(user)
      data_attributes = hovercard_data_attributes_for_user(user)

      content_tag(
        :a,
        "@#{user}",
        href: user_path(user),
        class: "user-mention",
        **data_attributes,
      )
    end

    def t(key, **options)
      I18n.t("achievements.substituted_text.#{key}", locale: @locale, **options)
    end

    # Substitution methods

    substitution :threshold do
      tier.threshold
    end

    substitution :threshold_ordinal do
      tier.threshold.ordinalize
    end

    substitution :threshold_duration do
      # Yes, Durations use .inspect instead of .to_s to pretty-print.
      # .to_s returns "300" while .inspect returns "5 minutes".
      tier.threshold.inspect
    end

    substitution :link do
      achievable_class = achievement.achievable.class
      link_to(achievable_class::LINK_TEXT, achievable_class::LINK_HREF)
    end

    substitution :achieving_user_login do
      achievement.async_user.then do |user|
        if login = user&.login
          "@#{login}"
        else
          "(#{t("deleted_user")})"
        end
      end
    end

    substitution :achieving_user_name do
      achievement.async_user.then do |user|
        next "(#{t("deleted_user")})" unless user

        user.async_profile.then do |profile|
          profile&.name&.presence || user.login
        end
      end
    end

    substitution :reaction_count_phrase do |visible, issueish|
      next t("many_reactions") unless visible

      reaction_count = issueish.to_issue.reactions.size
      t("reaction_count_phrase", count: reaction_count)
    end

    substitution :coauthor_login_mention do |visible, pr|
      next t("an_unknown_user") unless visible

      emails_to_skip = Set.new
      actors = []

      pr.changed_commits.each do |commit|
        emails = commit.author_emails
        next unless emails.size > 1

        commit.author_actors.each do |actor|
          email = actor.display_email.downcase
          next if emails_to_skip.include?(email)
          emails_to_skip << email
          actors << actor
        end
      end

      user_promises = actors.map { |actor| actor.async_visible_user(current_user) }
      Promise.all(user_promises).then do |users|
        users = users.reject { |user| user.nil? || user.id == achievement.user_id }

        if users.empty?
          # Co-authors not GitHub users, spammy, blocked, etc
          t("an_unknown_user")
        elsif users.size == 1
          render_user_mention(users.first)
        else
          to_sentence(users.map(&method(:render_user_mention)))
        end
      end
    end

    substitution :repository_with_pronoun do |visible, achievement_repository_list|
      unlockings_count = visible ? achievement_repository_list.repositories.size : 0

      if unlockings_count > 1
        if unlockings_count > repository_limit
          t("repository_pronoun.more")
        else
          t("repository_pronoun.other")
        end
      else
        t("repository_pronoun.one")
      end
    end

    substitution :acv_count_with_repository do
      achievement.async_user.then do |user|
        if count = user&.acv_contribution_count
          if count > 3
            t("repository_count_phrase.unspecified")
          else
            t("repository_count_phrase", count: count)
          end
        else
          t("repository_count_phrase.unknown")
        end
      end
    end

    substitution :nasa_2020_count_with_repository do
      achievement.async_user.then do |user|
        if highlight = user&.displayable_profile_highlights&.nasa_2020&.first
          count = highlight.contribution_count

          if count > 3
            t("repository_count_phrase.unspecified")
          else
            t("repository_count_phrase", count: count)
          end
        else
          t("repository_count_phrase.unknown")
        end
      end
    end

    substitution :public_sponsors_sum_and_types do
      achievement.async_user.then do |user|
        next t("org_or_user_count_phrase.unknown") unless user

        if user.public_sponsoring_count > 0
          if user.public_sponsoring_count == 1
            t("org_or_user_count_phrase.one")
          else
            t("org_or_user_count_phrase", count: user.public_sponsoring_count)
          end
        else
          if user.inactive_public_sponsoring_count == 1
            t("org_or_user_count_phrase.inactive_one")
          else
            t("org_or_user_count_phrase.inactive", count: user.inactive_public_sponsoring_count)
          end
        end
      end
    end

    class StringContext
      def safe_join(parts)
        parts.join("")
      end

      def content_tag(_tag, text, **kwargs)
        text
      end

      def link_to(text, _href)
        text
      end

      def to_sentence(array)
        array.to_sentence
      end

      def hovercard_data_attributes_for_user(_user)
        {}
      end

      def user_path(_user)
        ""
      end

      def repository_path(_repo)
        ""
      end

      def repository_limit
        3
      end
    end
  end
end
