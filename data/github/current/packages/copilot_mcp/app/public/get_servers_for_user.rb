# typed: strict
# frozen_string_literal: true

class GetServersForUser
  sig { params(user: User).returns(T::Array[McpServer]) }
  def self.call(user:)
    McpServerConfig
      .where(user_id: user.id)
      .where.not(access_token: nil)
      .includes(:mcp_server)
      .map(&:mcp_server)
      .compact
  end
end
