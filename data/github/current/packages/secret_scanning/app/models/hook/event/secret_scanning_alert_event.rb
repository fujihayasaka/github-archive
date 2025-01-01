# typed: true
# frozen_string_literal: true

class Hook::Event::SecretScanningAlertEvent < Hook::Event
  include GitHub::Memoizer
  include GitHub::TokenScanning::SecretScanningHelper

  supports_targets(*DEFAULT_TARGETS)

  description "Secrets scanning alert created, resolved, reopened, validated, or publicly leaked."

  event_attr :action, :repository_id, :alert_number, required: true

  # An optional Repository field to avoid needing to query for one.
  # This is defined as a separate attr instead of `event_attr`
  # because `event_attr`s get serialized, which causes an error with Repository.
  # This means that the repo attr will be nil after delivering to the queue,
  # and so the optimization will only apply before queueing, but not after.
  sig { returns(T.nilable(Repository)) }
  attr_accessor :repo

  # A replacement for the normal #queue method
  # that takes a Repository parameter to avoid needing to query for one.
  sig do
    params(
      repo: Repository,
      action: Symbol,
      alert_number: Integer,
    ).void
  end
  def self.queue_with_repo(repo:, action:, alert_number:)
    now = Time.now
    event = Hook::Event::SecretScanningAlertEvent.new(
      repository_id: repo.id,
      action:,
      alert_number:,
      triggered_at: now,
    )
    event.repo = repo
    event.attributes[:queued_at] = now.to_f
    event.deliver_later
  end

  sig { returns(Repository) }
  memoize def target_repository
    rpo = repo
    return with_read { Repository.find_by(id: repository_id) } if rpo.nil?
    rpo
  end

  def target_organization
    owner = with_read { target_repository.owner }
    owner.organization? ? owner : nil
  end

  sig { returns(T.nilable(GitHub::TokenScanning::Service::Token)) }
  memoize def secret
    get_secret_from_service
  end

  sig { returns(T.nilable(GitHub::TokenScanning::Service::Token)) }
  def get_secret_from_service
    feature_flags = []
    response = GitHub::TokenScanning::Service::Client.new(nil).get_token(
      repository_id: repository_id,
      token_id: alert_number,
      feature_flags: feature_flags,
    )
    result = response&.data&.token

    return nil if result.nil?
    GitHub::TokenScanning::Service::Client.wrap_token(result, target_repository)
  end

  def resolver
    return nil unless secret

    User.find_by(id: secret&.resolver_id)
  end

  # Maps to the 'sender' object in the event payload. For 'alert created' events, the sender is github.
  def actor
    return @actor if defined? @actor

    @actor = with_read { resolver || User.find_by_login("github") }
  end

  def deliverable?
    !!secret
  end

  private

  def with_read
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end
end
