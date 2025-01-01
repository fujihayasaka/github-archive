# typed: false
# frozen_string_literal: true

# Functionality related to user emails as they relate to authoring commits:
# - Determining the email to use for a new commit created by a User
# - Finding users based on git commit emails
module User::AuthorEmailsDependency
  extend ActiveSupport::Concern

  class_methods do
    def find_by_email(email, business: nil)  # rubocop:disable GitHub/FindByDef
      return nil unless email
      return nil unless GitHub::UTF8.valid_email?(email)

      if UserEmail.belongs_to_a_bot?(email)
        Bot.find_by_email(email)
      elsif email =~ StealthEmail::STEALTH_EMAIL_REGEX
        User.find_by_id($1)
      elsif email =~ StealthEmail::OLD_STEALTH_EMAIL_REGEX
        User.find_by_login($1)
      else
        email = business.add_emu_shortcode_to_emails(email) if business.present?
        User.joins(:emails).where("user_emails.email" => email).readonly(false).first
      end
    end

    # Maps email addresses to Users.  It accepts a hash of business to array of emails mapping
    #
    # emails - A Hash of String email address arrays, keyed by a Business
    #
    # Returns a Hash like {"foo@bar.com" => <User>, ...}
    def find_by_emails_with_business(emails)  # rubocop:disable GitHub/FindByDef
      converted = emails.flat_map { |business, emails| business ? business.add_emu_shortcode_to_emails(emails) : emails }

      find_by_emails(converted.uniq.compact)
    end

    # Maps email addresses to Users
    #
    # emails - An Array of String email addresses.
    # business - an emu business associated with the email
    #
    # Returns a Hash like {"foo@bar.com" => <User>, ...}
    def find_by_emails(emails, business: nil, verified: false, skip_private_profiles: false)  # rubocop:disable GitHub/FindByDef
      GitHub.dogstats.distribution_time("user.find_by_emails") do
        emails = Array(emails).select { |e| GitHub::UTF8.valid_email?(e) }

        bot_emails, user_emails = emails.partition { |e| UserEmail.belongs_to_a_bot?(e) }
        bot_hash = Bot.find_by_emails(bot_emails)

        # add short code to an email when business is present and it is a emu
        user_emails_with_shortcodes = user_emails
        user_emails_with_shortcodes = business.add_emu_shortcode_to_emails(user_emails_with_shortcodes) if business.present?
        user_emails_with_shortcodes = user_emails_with_shortcodes.map { |email| email.downcase }
        user_emails = user_emails.map { |email| email.downcase }

        stealth_emails = user_id_and_email_from_stealth_emails(user_emails)
        users = User.select("users.*, user_emails.email as user_email, user_emails.state as user_email_state").
                where("user_emails.email IN (?)", user_emails_with_shortcodes).
                joins("INNER JOIN user_emails ON users.id = user_emails.user_id")
        users = users.merge(UserEmail.verified) if verified
        users = users.where(private_profile: false) if skip_private_profiles
        user_email_hash = Hash[users.map { |user| [user.remove_shortcode(user.user_email.downcase, business: business), user] }]

        user_email_hash.merge(stealth_emails_hash(stealth_emails)).merge(bot_hash)
      end
    end

    # Map commit objects to Users through the committer's email address.
    #
    # commits   - An Array of Commits.
    # user_type - Symbol defining which user property is used: :author or
    #             :committer.
    # business  - an emu business associated with the email
    #
    # Returns a Hash like {"foo@bar.com" => <User>, ...}
    def find_by_commits(commits, user_type = :author, business: nil)  # rubocop:disable GitHub/FindByDef
      emails = commits.inject([]) do |all, commit|
        if user_type != :author
          all << commit.committer_email
        end
        if user_type != :committer
          all << commit.author_email
        end
        all
      end
      emails.delete_if do |em|
        em.to_s.downcase.strip.blank?
      end
      emails.uniq!

      return {} if emails.blank?
      find_by_emails(emails, business: business)
    end

    private

    # Finds the stealth ides if they exist in the pass in emails
    # and pulls out the user id from each
    #
    # emails - An Array of String email addresses.
    #
    # Returns an Array like [{id: 1, email: "1+bob@users.noreply.github.com"}, ...]
    def user_id_and_email_from_stealth_emails(emails)
      emails = Array(emails)

      logins_by_old_email = emails.each_with_object({}) do |email, hash|
        if match = StealthEmail::OLD_STEALTH_EMAIL_REGEX.match(email)
          hash[email] = match[1]
        end
      end

      old_email_logins = logins_by_old_email.values
      users_by_login = if old_email_logins.empty?
        {}
      else
        User.where(login: old_email_logins).index_by do |user|
          user.login.downcase
        end
      end

      users_by_old_email = logins_by_old_email.each_with_object({}) do |(email, login), hash|
        # The login from the email may not be of the same case as that in the User
        # record, so we compare them downcased.
        hash[email] = users_by_login[login.downcase]
      end

      emails.map do |e|
        if e =~ StealthEmail::STEALTH_EMAIL_REGEX
          { id: $1.to_i, email: e }
        elsif e =~ StealthEmail::OLD_STEALTH_EMAIL_REGEX
          if user = users_by_old_email[e]
            { id: user.id, email: e }
          end
        end
      end.compact
    end

    # Finds the users associated with each id+login@domain stealth emails
    # and returns it in the format expected by the find_by_emails return
    #
    # stealth_emails - An Array of Hashes of stealth email information
    #
    # Returns a Hash like {"1+bob@users.noreply.github.com" => <User>, ...}
    def stealth_emails_hash(stealth_emails)
      email_hash = {}
      if stealth_emails.any?
        # these are always verified
        users = User.select("users.*, 'verified' as user_email_state").
                where("users.id IN (?) and type != 'Organization'", stealth_emails.map { |item| item[:id] })
        if users.any?
          users.each do |user|
            found_stealth_emails = stealth_emails.select { |s| s[:id] == user.id }

            found_stealth_emails.each do |stealth_email|
              email_hash[stealth_email[:email]] = user
            end
          end
        end
      end
      email_hash.compact
    end
  end

  # Public: Gets a list of emails the user can use to author a commit
  #
  # Return type: [] | [String]
  # Returns [] if the user has email privacy enabled, if the current instance of GitHub
  #   does not have this feature enabled, if the feature flag is not enabled, or if the user
  #   only has one verified and visible email.
  # Else, returns the list of verified, visible emails
  def author_emails
    return [] if use_stealth_email? || !GitHub.choose_commit_email_enabled?
    emails = self.emails.verified.visible
    # We don't want to display the dropdown if the user only has one email to choose since they have no other option
    emails.count > 1 ? emails.map(&:email) : []
  end

  def default_author_email_cache_key(repository)
    "user:default_author_email:#{repository.id}:#{self.id}"
  end

  # Public: Gets the cached default author email for a commit in a repository
  #
  # repository - The Repository in which the user is committing.
  # current_sha - The sha of the current pull request branch, if available
  #
  # Return type: nil | String
  # Returns nil if author_emails returns [], or if repository is nil
  # If the user is a contributor to the repository, returns the last email the user contributed with
  # Else, if something above fails or if the above conditions aren't true, returns the user's git_author_email
  def default_author_email(repository, current_sha = nil)
    return unless author_emails.any? && repository

    default_email = Users::Kv.store.get(default_author_email_cache_key(repository)).value { nil }
    if default_email && author_emails.include?(default_email)
      default_email
    else
      uncached_default_author_email(repository, current_sha)
    end
  end

  def uncached_default_author_email(repository, current_sha)
    if repository.contributor?(self)
      # default to the last email they committed with on this repository or current branch
      branches_to_search = [repository.default_oid, current_sha].compact
      commit_sha = begin
        repository.rpc.list_revision_history_multiple(branches_to_search, authors: author_emails, max: 1, timeout: 1).first
      rescue GitRPC::Timeout
        nil
      end
      if commit_sha
        last_commit = repository.commits.find(commit_sha)
        return last_commit.author_email if last_commit&.author_email
      end
    end

    git_author_email
  end

  def update_default_author_email_cache(repository, author_email, degrade: true)
    ActiveRecord::Base.connected_to(role: :writing) do
      Users::Kv.store.set(default_author_email_cache_key(repository), author_email)
    end
  rescue GitHub::KV::UnavailableError
    raise unless degrade
  end
end
