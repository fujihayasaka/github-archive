# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class Commit
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :commit, :repository

    # Show a tooltip on commits that have an unlinked author when the current user
    # has write access.
    #
    # type - Either :author or :committer.
    #
    # Returns HTML safe String
    def hint_for_unlinked_email(type)
      return if current_user.is_enterprise_managed?
      return unless repository.pushable_by?(current_user)

      help_url = "#{GitHub.help_url}/articles/setting-your-email-in-git"

      if UserEmail.generic_domain? email_for_commit(type)
        email = StealthEmail.new(current_user).email
        title = "Unrecognized #{type}. If this is you and you want to keep your email private, change your local git email setting to '#{email}'."
        hint_icon(title, help_url)

      elsif user_for_commit(type).blank?
        email = email_for_commit(type)

        if !UserEmail.new(email: email).valid?
          title = "Invalid #{type} email. If this commit was made by you, check your local git email setting."
          hint_icon(title, help_url)
        else
          url   = urls.settings_email_preferences_path
          title = "Unrecognized #{type}. If this is you, make sure #{email} is associated with your account. Click to add email addresses in your account settings."
          hint_icon(title, url)
        end
      end
    end

    # Display a form that adds the committer's email address to your account if:
    #
    #   - You're logged in
    #   - You can push to the repository
    #   - It's not a generic domain like `hubot@local`
    #   - It's not a completely bogus address like `12`
    #   - We think you might be the author based on text matching your account
    #     info with the committed email address.
    #
    # Returns true if the form should be shown to the current user.
    def show_claim_email_form?
      return false if logged_in? && current_user.is_enterprise_managed?

      new_user = logged_in? && current_user.created_at > 6.months.ago

      tags = ["action:unclaimed"]

      # Track how many times unclaimed commits are viewed.
      tags << "type:view" if !author?

      # Track how many times unclaimed commits are viewed by new users.
      tags << "type:view_by_new_user" if !author? && new_user

      email = email_for_commit(:author) || ""
      show =
        new_user &&
        repository.pushable_by?(current_user) &&
        UserEmail.new(email: email).valid? &&
        !UserEmail.generic_domain?(email) &&
        !author? &&
        possible_author?

      # Compare views to how many times the form is actually shown.
      tags << "type:show_claim_form" if show

      # Compare views to how many times the form is actually shown to new users.
      tags << "type:show_claim_form_to_new_user" if show && new_user

      GitHub.dogstats.increment("commit_show_view", tags: tags)

      show
    end

    def weirich?
      repository.id == 15803047 && # "jimweirich/wyriki"
        commit.oid == "d28fac7f18aeacb00d8ad3460a0a5a901617c2d4"
    end

    def current_review
      @current_review
    end

    private

    def author?
      !user_for_commit(:author).nil?
    end

    def committer?
      !user_for_commit(:committer).nil?
    end

    # Determine if it's possible that the current user is the author of the
    # commit. Compares commit names and emails to the current user's login, name,
    # and emails, looking for similarities.
    #
    # Returns true if the user may have authored this commit.
    def possible_author?
      user_data = [current_user.display_login] + current_user.emails.map { |email| email.email }
      user_data += [current_user.profile.name, current_user.profile.email] if current_user.profile
      user_data = user_data.compact.map { |text| normalize(text) }.uniq

      commit_data = [
        commit.author_name,
        commit.author_email,
        commit.committer_name,
        commit.committer_email,
      ].compact.map { |text| normalize(text) }.uniq

      commit_data.each do |a|
        user_data.each do |b|
          percent = GitHub::Levenshtein.similarity(a, b)
          return true if percent >= 0.33
        end
      end

      false
    end

    # Strip non-word characters from the string to make it easier to compare
    # with the Levenshtein distance algorithm. Strips any email domain names
    # from the text so only the user's inbox component is used in the comparison.
    #
    # text - The String to clean.
    #
    # Returns a String.
    def normalize(text)
      return "" if text.nil?
      text = text.split("@").first || ""
      text.gsub(/[\W_]/, "").downcase
    end

    # Is there a GitHub user available for a given commit? If so, find it.
    #
    # type - Either :author or :committer.
    #
    # Returns User if one is found
    def user_for_commit(type)
      @commit_user_by_type ||= Hash.new do |hash, type|
        email = email_for_commit(type)

        business = repository&.enterprise_managed_business
        email = business.add_emu_shortcode_to_emails(email) if business&.enterprise_managed_user_enabled?

        hash[type] = User.find_by_email email
      end

      @commit_user_by_type[type]
    end

    # Is there an email saved into a given commit? If so, find it.
    #
    # type - Either :author or :committer.
    #
    # Returns an email String if one is found
    def email_for_commit(type)
      case type
      when :author
        commit.author_email.to_s
      when :committer
        commit.committer_email.to_s
      end
    end

    def hint_icon(title, url)
      icon = helpers.octicon("question")
      css = "hint tooltipped tooltipped-s tooltipped-multiline"
      helpers.content_tag :a, icon, :href => url, :class => css, "aria-label" => title # rubocop:disable Rails/ViewModelHTML
    end
  end
end
