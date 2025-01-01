# typed: true
# frozen_string_literal: true

class StratocasterEventPrefiller
  BATCH_SIZE = 100

  # Params:
  #
  # events - an Array of Stratocaster::Events
  def initialize(events)
    @events = events
  end

  # Public: Preloads requested associations.
  #
  # Params:
  #
  # associations - a symbol or Array of symbols with requested associations.
  #   :commit_authors - commit authors in push events
  #   :repos - repository associated with Stratocaster::Event objects
  #   :senders - the user who created the event in Stratocaster::Event objects
  #
  # Returns nothing.
  def preload(*associations)
    Array.wrap(associations).flatten.each do |assoc|
      case assoc.to_sym
      when :commit_authors then
        if FeatureFlag.vexi.enabled?(:preload_commits_with_enterprise, default: false)
          preload_commit_authors_with_enterprise
        else
          preload_commit_authors
        end
      when :repos then preload_repos
      when :senders then preload_senders
      else
        if Rails.env.test?
          raise "#{assoc} is not a valid Stratocaster event association"
        end
      end
    end
  end

  private

  def preload_commit_authors
    events_by_emails = @events.select(&:push_event?).group_by(&:commit_author_emails)
    emails = events_by_emails.keys.flatten.uniq

    users_by_email = {}
    emails.each_slice(BATCH_SIZE) do |email_batch|
      users = User.find_by_emails(email_batch)
      users.each do |(email, user)|
        users_by_email[email.downcase] = user
      end
    end

    events_by_emails.each do |emails, email_events|
      emails.each do |email|
        user = users_by_email[email]
        next unless user

        email_events.each { |event| event.set_commit_author_for_email(email, user) }
      end
    end
  end

  def preload_commit_authors_with_enterprise
    push_events = @events.select(&:push_event?)

    # { "[mona@github.com, othermona@github.com]" => [PushEvent] }
    # Group events by commit_author_email for quick lookup when setting the user
    events_by_emails = push_events.group_by(&:commit_author_emails)

    # { "123" => [PushEvent] }
    # Group push events by repo_id to avoid duplicate Business lookups
    events_by_repo_id = push_events.group_by(&:repo_id)

    users_by_email = {}
    repos_by_id = Repository.where(id: events_by_repo_id.keys).group_by(&:id)

    events_by_repo_id.each do |repo_id, events|
      repo = repos_by_id[repo_id]&.first
      business = repo.enterprise_managed_business if repo&.is_enterprise_managed?

      emails = events.map(&:commit_author_emails)
      users = User.find_by_emails(emails.flatten.uniq, business: business)
      users.each do |(email, user)|
        users_by_email[email.downcase] = user
      end

      events_by_emails.each do |emails, email_events|
        emails.each do |email|
          user = users_by_email[email]
          next unless user

          email_events.each { |event| event.set_commit_author_for_email(email, user) }
        end
      end
    end
  end

  def preload_repos
    events_by_repo_id = @events.group_by(&:repo_id)
    repo_ids = events_by_repo_id.keys.compact
    repos_by_id = {}

    repo_ids.each_slice(BATCH_SIZE) do |repo_id_batch|
      repos = Repository.includes(:owner, :organization, :primary_language).where(id: repo_id_batch)
      repos.each { |repo| repos_by_id[repo.id] = repo }
    end

    events_by_repo_id.each do |repo_id, repo_events|
      next unless repo_id

      repo = repos_by_id[repo_id]
      next unless repo

      repo_events.each { |event| event.repo = repo }
    end
  end

  def preload_senders
    events_by_sender_id = @events.group_by(&:sender_id)
    user_ids = events_by_sender_id.keys.compact

    users_by_id = {}
    user_ids.each_slice(BATCH_SIZE) do |user_id_batch|
      users = User.where(id: user_id_batch).
        includes(:profile) # used in Event#sender_name
      users.each { |user| users_by_id[user.id] = user }
    end

    events_by_sender_id.each do |sender_id, sender_events|
      next unless sender_id

      user = users_by_id[sender_id]
      next unless user

      sender_events.each { |event| event.sender = user }
    end
  end
end
