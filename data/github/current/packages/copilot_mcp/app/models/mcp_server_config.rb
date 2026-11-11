# typed: strict
# frozen_string_literal: true

class McpServerConfig < ApplicationRecord::Copilot
  include Instrumentation::Model

  encrypts :code_verifier
  encrypts :access_token
  encrypts :refresh_token

  belongs_to :user, class_name: "::User"
  belongs_to :mcp_server

  validates :display_name, presence: true, uniqueness: { scope: :user_id }
  validates :mcp_server, presence: true
  validates :user, presence: true

  after_destroy_commit do |record|
    McpOauth::Cleanup.remove_unused_server(record.mcp_server)
  end

  USER_AUTH_EVENT_TYPES = T.let({
    installed: :installed,
    uninstalled: :uninstalled
  }, T::Hash[Symbol, Symbol])

  sig { returns(T::Boolean) }
  def access_token_expired?
    return true if access_token_expires_at.nil?
    Time.current >= access_token_expires_at
  end

  sig do
    params(
      access_token: String,
      refresh_token: String,
      expires_in: Integer
    ).void
  end
  def update_tokens!(access_token:, refresh_token:, expires_in:)
    Copilot::Helpers.with_write do
      update!(
        access_token: access_token,
        refresh_token: refresh_token,
        access_token_expires_at: Time.current + expires_in.seconds
      )
    end
  rescue ActiveRecord::ActiveRecordError => e
    raise McpOauth::Errors::TokenExchangeError.new(e)
  end

  sig { params(event_type: Symbol, user: ::User).void }
  def record_event!(event_type, user)
    unless USER_AUTH_EVENT_TYPES.key?(event_type)
      raise ArgumentError, "Invalid event type: \#{event_type}"
    end
    instrument(
      USER_AUTH_EVENT_TYPES[event_type],
      prefix: :mcp_server,
      actor: user,
      mcp_server_id: mcp_server_id,
      mcp_server_config_id: id,
      mcp_server_url: mcp_server&.url
    )
  end
end
