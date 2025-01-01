# typed: true
# frozen_string_literal: true

# Public: A GitActor represents the identity and time information associated
# with a Git action (e.g., authoring a commit, committing a commit, creating a
# tag).
class GitActor
  include ActiveModel::Validations
  include PreloadableAttributes

  # NOTE: This has been copied to `vendor/gitrpc/lib/gitrpc/backend/gh_graph/graph_data`
  #       and the two should be kept in sync until the duplication can be eliminated.
  SIGNATURE_MATCHER = /\A(?<name>.+)\s\<(?<email>.+@.+)\>\z/

  validates_presence_of :name, :email

  validates_each :name, :email do |record, attr, value|
    if value.include?("\n")
      record.errors.add attr, "can't contain a newline character"
    end
  end

  validates_each :name, :email do |record, attr, value|
    if value =~ /[<>]/
      record.errors.add attr, "can't contain '<' or '>'"
    end
  end

  # Public: Initialize a GitActor.
  #
  # name       - The String name of the actor.
  # email      - The String email address of the actor.
  # time       - The String time that the action occurred in ISO 8601 format.
  # repository - The Repository to which this git actor belongs.
  def initialize(email: nil, name: nil, time: nil, repository: nil)
    @email      = email
    @name       = name
    @time       = time
    @repository = repository
  end

  attr_reader :email, :name, :time

  def display_name
    GitHub::Encoding.try_guess_and_transcode(name)
  end

  def display_email
    GitHub::Encoding.try_guess_and_transcode(email)
  end

  # Filter for the associated bot or actor, based on whether they should be
  # visible to the given viewer
  #
  # viewer - a User object
  #
  # Returns a Promise that resolves to a Bot or User, or nil if the actor is
  # spammy, suspended, blocked, or otherwise hidden from the given viewer
  def async_visible_actor(viewer)
    return async_bot if UserEmail.belongs_to_a_bot?(email)
    async_visible_user(viewer)
  end

  def visible_actor(viewer)
    async_visible_actor(viewer).sync
  end

  def async_visible_user(viewer)
    @async_visible_user_for ||= Hash.new do |hash, viewer|
      hash[viewer] = async_user.then do |user|
        next nil if user&.hide_from_user?(viewer)
        async_is_blocked_by_or_blocking_repo_owner?.then do |is_blocked_or_blocking|
          next nil if is_blocked_or_blocking
          user
        end
      end
    end

    @async_visible_user_for[viewer]
  end

  def async_visible_avatar_url(viewer, size: 32)
    async_visible_actor(viewer).then { |user| avatar_url_for_user(user, size) }
  end

  def async_avatar_url(size: 32)
    async_actor.then { |user| avatar_url_for_user(user, size) }
  end

  def commits_path_uri
    return @commits_path_uri if defined? @commits_path_uri
    @commits_path_uri = async_commits_path_uri.sync
  end

  def async_commits_path_uri
    return Promise.resolve(nil) unless @repository

    async_actor.then do |user|
      next unless user
      @repository.async_commits_path_uri(author: user.display_login)
    end
  end

  def actor
    return @actor if defined? @actor

    @actor = async_actor.sync
  end

  def async_actor
    return async_bot if UserEmail.belongs_to_a_bot?(email)
    async_user
  end

  def async_user
    return Promise.resolve(@async_user) if defined?(@async_user)

    if @repository.kind_of?(Repository)
      @repository.async_enterprise_managed_business.then do |business|
        @async_user ||= ::Platform::Loaders::UserByEmail.load(email, business: business)
      end
    else
      @async_user ||= ::Platform::Loaders::UserByEmail.load(email)
    end
  end

  def async_bot
    return @async_bot if defined? @async_bot

    @async_bot = ::Platform::Loaders::BotByEmail.load(email)
  end

  # Is this actor blocked by the repo owner or blocking the repo owner?
  #
  # Returns false by default unless user abuse mitigation is enabled.
  #
  # Returns Promise that resolves to a Boolean
  def async_is_blocked_by_or_blocking_repo_owner?
    return Promise.resolve(false) unless GitHub.user_abuse_mitigation_enabled?
    return Promise.resolve(false) unless @repository
    @async_is_blocked_by_or_blocking_repo_owner ||= async_actor.then do |actor|
      next false unless actor && actor.is_a?(User)
      @repository.async_owner.then do |repo_owner|
        Promise.all([
          actor.async_blocked_by?(repo_owner), repo_owner.async_blocked_by?(actor)
        ]).then do |user_blocked_by_repo_owner, repo_owner_blocked_by_user|
          user_blocked_by_repo_owner || repo_owner_blocked_by_user
        end
      end
    end
  end

  # Public: Provides a Hash representation of this actor, suitable for passing
  # to GitRPC methods that expect an actor Hash.
  #
  # Returns a Hash.
  def to_gitrpc_hash
    {
      "name" => name,
      "email" => email,
      "time" => time,
    }
  end

  private

  def avatar_url_for_user(user, size)
    return user.primary_avatar_url(size) if user
    fallback_avatar_url(size)
  end

  def fallback_avatar_url(size)
    if GitHub.gravatar_enabled?
      src = ::User::AvatarList.gravatar_url_for(email, size)
      GitHub::HTML::CamoFilter.asset_proxy_url(src)
    else
      ::User::AvatarList.default_image_url
    end
  end
end
