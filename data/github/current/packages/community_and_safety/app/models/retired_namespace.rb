# typed: true
# frozen_string_literal: true

require "octolytics/pond"

class RetiredNamespace < ApplicationRecord::Ballast
  include GitHub::Relay::GlobalIdentification

  # Number of clones a repo must have in a week to be retired
  WEEKLY_CLONE_THRESHOLD = 100

  # Number of action uses a repo must have in a week to be retired
  WEEKLY_ACTION_USES_THRESHOLD = 100

  belongs_to :owner, class_name: "User", foreign_key: "owner_login", primary_key: "login" # rubocop:todo Rails/InverseOf

  validates_presence_of :owner_login, :name
  validates_uniqueness_of :name, scope: :owner_login, case_sensitive: false
  validates_format_of :name_with_owner, with: Repository::NAME_WITH_OWNER_PATTERN

  before_validation :downcase_name_and_owner_login
  after_create :instrument_retire_namespace
  after_destroy :instrument_unretire_namespace

  default_scope { order("owner_login ASC", "name ASC") }

  class << self
    # Public: Check if a retired namespace exists for a specified owner and
    #         repository name.
    #
    # owner - The String repository owner login.
    # name  - The String repository name.
    #
    # Returns a RetiredNamespace|nil.
    def for(owner:, name:)
      find_by(owner_login: owner.downcase, name: name.downcase)
    end

    # Public: Return all retired namespaces for a repository owner.
    #
    # owner - The User repository owner, or the String owner login, to get
    #         retired namespaces for.
    #
    # Returns an RetiredNamespace::ActiveRecord_Relation.
    def for_owner(owner)
      if owner.is_a?(String)
        # If a String login is passed in, try to look up the user if it exists.
        # If it doesn't, we fall back to just looking up records by login.
        user = User.find_by(login: owner)
        owner = user || owner
      end

      login = owner.is_a?(User) ? owner.login : owner
      scope = where(owner_login: login.downcase)

      if owner.is_a?(User)
        scope = scope.or(where(owner_id: owner.id))
      end

      scope
    end

    # Public: Retires a namespace.
    #
    # owner - The User repository owner, or the String owner login, to retire
    #         a namespace for.
    # name  - The String repository name.
    #
    # Returns a RetiredNamespace::Result.
    def retire(owner:, name:)
      if owner.blank? || name.blank?
        return Result.failure(
          namespace: nil,
          errors: ["Both `owner` and `name` are required"],
        )
      end

      login = owner.is_a?(User) ? owner.login : owner

      if namespace = self.for(owner: login, name: name)
        return Result.success(namespace: namespace)
      end

      attributes = {
        owner_login: login,
        name: name,
      }

      if owner.is_a?(User)
        attributes = attributes.merge({ owner_id: owner.id })
      end

      namespace = new(attributes)

      if namespace.save
        Result.success(namespace: namespace)
      else
        Result.failure(
          namespace: namespace,
          errors: namespace.errors.full_messages,
        )
      end
    end

    # Public: Unretires a namespace.
    #
    # owner - The User repository owner, or the String owner login, to unretire
    #         a namespace for.
    # name  - The String repository name.
    #
    # Returns a RetiredNamespace::Result.
    def unretire(owner:, name:)
      if owner.blank? || name.blank?
        return Result.failure(
          namespace: nil,
          errors: ["Both `owner` and `name` are required"],
        )
      end

      login = owner.is_a?(User) ? owner.login : owner
      namespace = self.for(owner: login, name: name)
      return Result.success(namespace: namespace) if namespace.blank?

      namespace.unretire
    end

    # Public: Unretire multiple namespaces by id.
    #
    # Returns a RetiredNamespace::Result
    # Exits early on the first failure
    def unretire_multiple(user:, ids:)
      ids.each do |id|
        result = RetiredNamespace.find_by!(owner: user, id: id).unretire
        return result unless result.success?
      rescue ActiveRecord::RecordNotFound
        return Result.failure(
          namespace: nil,
          errors: ["Retired namespace with id #{id} not found"],
        )
      end

      Result.success(namespace: nil)
    end

    # Retire a given repository's namespace
    #
    # repository - the Repository object
    #
    # Returns the RetiredNamespace or raises an error if invalid
    def create_from_repository!(repository)
      retire_redirects!(repository)
      create!(
        owner_id: repository.owner_id,
        owner_login: repository.owner_login,
        name: repository.name,
      )
    end

    # Retire a given repository's redirected namespaces
    #
    # repository - the Repository object
    def retire_redirects!(repository)
      redirects = repository.redirects.map do |redirect|
        owner_login, name = redirect.repository_name.downcase.split("/")
        { owner_login: owner_login, name: name }
      end.uniq

      # To avoid an N+1 by calling retired? for each redirect, batch query
      # existing namespaces so that we can skip already-retired ones below
      retired_namespaces = RetiredNamespace.where(
        owner_login: redirects.map { |h| h[:owner_login] },
        name: redirects.map { |h| h[:name] },
      ).map { |rn| { owner_login: rn.owner_login, name: rn.name } }

      (redirects - retired_namespaces).each do |redirect|
        create!(redirect.merge(owner_id: repository.owner_id))
      end
    end

    # Should the given repository's namespace be retired?
    #
    # Repositories must be public and must have received more clones
    # than the WEEKLY_CLONE_THRESHOLD in the previous week.
    #
    # repository - the Repository object or a name with owner string
    # rescue_kv  - if true, gracefully degrade if GitHub::KV is unavailable
    #
    # Returns true if it should be retired, otherwise false
    def should_retire?(repository, rescue_kv: false)
      return false unless GitHub.retired_namespaces_on_deletion_enabled?
      repository = Repository.with_name_with_owner(repository) unless repository.is_a?(Repository)
      return true if repository.action_ever_listed?
      return false unless repository.public?
      # We can't check `is_user_pages_repo?` here, because if a user renamed their account, it would return false
      # at this point and incorrectly retire a Pages namespace. So instead we err towards not retiring repositories
      # with names that look like User Pages repository names.
      return false if repository.name.ends_with?(".#{repository.owner.pages_host_name}")
      return true if clones_in_the_past_week(repository.id) >= WEEKLY_CLONE_THRESHOLD
      actions_usage = if rescue_kv
        begin
          Actions::RepositoryUsage.uses_in_the_past_week(repository.id)
        rescue GitHub::KV::UnavailableError
          WEEKLY_ACTION_USES_THRESHOLD + 1
        end
      else
        Actions::RepositoryUsage.uses_in_the_past_week(repository.id)
      end
      actions_usage >= WEEKLY_ACTION_USES_THRESHOLD
    rescue Octolytics::Error => error
      Failbot.report!(error)
      true # If the Pond request fails, default to true to avoid false negatives
    end

    # Does the given repository conflict with a retired namespace?
    #
    # owner_or_nwo - the repository owner, or a full name with owner string
    # name         - if owner is passed as the first argument, the repo name
    #
    # Returns true if the namespace is retired, otherwise false
    def retired?(owner_or_nwo, name = nil)
      owner_or_nwo, name = owner_or_nwo.split("/") if name.nil?
      RetiredNamespace.exists?(owner_login: owner_or_nwo.downcase, name: name.downcase)
    end

    private

    # Get the number of clones in the last week for the given repository ID
    # since the Pond API doesn't work in DEV environment,
    # this ternary allows deletions to function
    def clones_in_the_past_week(repository_id)
      GitHub.dogstats.increment "retired_namespace.count_recent_clones"
      Rails.env.development? ? 0 : GitHub.pond_client.counts(repository_id, "clone", "week").data["data"]["count"].to_i
    end
  end

  # Returns the retired namespace's name with owner string
  def name_with_owner
    @name_with_owner ||= [owner_login, name].join("/")
  end
  alias_method :nwo, :name_with_owner

  # Returns the retired namespace's name with owner display string
  def name_with_display_owner
    @name_with_display_owner ||= [User.to_display_login(owner_login), name].join("/")
  end

  # Public: Indicates if this retired namespace can be reused by an actor.
  #
  # actor - The User trying to reclaim the namespace.
  #
  # Returns a Boolean.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def claimable_by?(actor)
    return false unless actor.present?

    # If the actor is the owner of the namespace, they can reclaim it.
    return true if actor.id == owner_id

    # If the actor owns the owning organization, they can reclaim the namespace.
    org = Organization.find_by(id: owner_id)
    return false unless org

    org.adminable_by?(actor)
  end

  # Public: Unretires the current namespace.
  #
  # Returns a RetiredNamespace::Result.
  def unretire
    if self.destroy
      Result.success(namespace: nil)
    else
      Result.failure(
        namespace: self,
        errors: errors.full_messages,
      )
    end
  end

  class Result
    attr_reader :namespace, :success, :errors
    alias_method :success?, :success

    # namespace - the RetiredNamespace that is being acted upon.
    # success   – a Boolean indicating the success of an operation.
    # errors    – an Array of String error messages.
    def initialize(namespace:, success:, errors:)
      @namespace = namespace
      @success   = success
      @errors    = errors
    end

    def self.success(namespace:)
      new(success: true, namespace: namespace, errors: [])
    end

    def self.failure(namespace:, errors:)
      new(success: false, namespace: namespace, errors: errors)
    end
  end

  private

  def downcase_name_and_owner_login
    this_name = self.name
    this_owner_login = self.owner_login

    self.name = this_name.dup.downcase if this_name
    self.owner_login = this_owner_login.dup.downcase if this_owner_login
  end

  def instrument_retire_namespace
    GitHub.dogstats.increment "retired_namespace.retire"
  end

  def instrument_unretire_namespace
    GitHub.dogstats.increment "retired_namespace.unretire"
  end
end
