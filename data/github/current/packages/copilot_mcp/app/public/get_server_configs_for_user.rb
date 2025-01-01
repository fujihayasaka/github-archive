# typed: strict
# frozen_string_literal: true

class GetServerConfigsForUser
  sig { params(user: User).returns(T::Array[McpServerConfig]) }
  def self.call(user:)
    McpServerConfig
      .where(user_id: user.id)
      .includes(:mcp_server)
      .compact
  end
end
