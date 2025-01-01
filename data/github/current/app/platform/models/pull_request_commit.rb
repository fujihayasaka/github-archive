# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestCommit
  include ::TextHelper
  include GitHub::Relay::GlobalIdentification
  extend Forwardable

  attr_reader :pull_request, :commit
  def_delegators :commit, :timeline_sort_by, :created_at

  def initialize(pull_request, commit)
    @pull_request = pull_request
    @commit = commit
  end

  def self.load_from_next_global_id(parsed_id)
    load(parsed_id.parts[:pull_id], parsed_id.parts[:commit_oid], new_format: true)
  end

  def self.load_from_global_id(id)
    pull_id, commit_oid = id.split(":", 2)
    new_format = pull_id =~ /\d+/ && GitRPC::Util.valid_full_oid?(commit_oid)
    load(pull_id, commit_oid, new_format: new_format)
  end

  def self.load(pull_id, commit_oid, new_format: true)
    if new_format
      Platform::Loaders::ActiveRecord.load(::PullRequest, pull_id.to_i, security_violation_behaviour: :nil).then do |pull|
        pull.async_load_pull_request_commit(commit_oid) if pull
      end
    else
      # Support for old format can be dropped once this counter stays at 0
      GitHub.dogstats.increment("platform.deprecation.pull_request_commit_global_id")

      pull_id = Platform::Helpers::NodeIdentification.from_global_id(pull_id).last
      commit_oid = Platform::Helpers::NodeIdentification.from_global_id(commit_oid).last

      async_pull = Platform::Objects::PullRequest.load_from_global_id(pull_id)
      async_commit = Platform::Objects::Commit.load_from_global_id(commit_oid)

      async_pull.then do |pull|
        async_commit.then do |commit|
          new(pull, commit)
        end
      end
    end
  end

  def self.id_for(pull_request, commit)
    "#{pull_request.id}:#{commit.oid}"
  end

  def id
    self.class.id_for(pull_request, commit)
  end

  def oid
    commit.oid
  end

  def async_message_headline_html_link
    Promise.all([pull_request.async_repository, commit.async_short_message_html]).then do |repository, message_headline_html|
      resource_path = UrlHelpers.pull_request_files_with_range_path(
        repository.owner_display_login,
        repository.name,
        pull_request.number,
        oid)

      link_markup_to commit_message_markdown(message_headline_html),
        resource_path,
        class: "Link--primary text-bold markdown-title"
    end
  end

  def view_context
    EmptyController.new.view_context
  end

  # Used by GraphQL authorization checks
  def async_pull_request
    Promise.resolve(pull_request)
  end

  def ==(other)
    super || (other.instance_of?(self.class) && other.state == state)
  end
  alias_method :eql?, :==

  def hash
    state.hash
  end

  protected

  def state
    [pull_request, commit]
  end
end
