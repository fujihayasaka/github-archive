# typed: true
# frozen_string_literal: true

class Hook::Event::SecretScanningAlertEvent < Hook::Event
  extend T::Sig
  include GitHub::Memoizer
  include GitHub::TokenScanning::SecretScanningHelper

  supports_targets(*DEFAULT_TARGETS)

  description "Secrets scanning alert created, resolved, reopened, or validated"

  event_attr :action, :repository_id, :alert_number, required: true

  def target_repository
    @repository ||= with_read { Repository.find_by(id: repository_id) }
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
