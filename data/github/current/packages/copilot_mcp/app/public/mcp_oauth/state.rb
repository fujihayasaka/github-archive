# typed: strict
# frozen_string_literal: true

class McpOauth::State
  sig { params(state: String).returns(T::Hash[Symbol, T.untyped]) }
  def self.parse(state)
    raise ArgumentError, "State cannot be blank" if state.blank?

    parts = state.split("|")
    raise ArgumentError, "Invalid state format" unless parts.size.between?(1, 2)

    mcp_server_config_id = T.let(parts[0].to_i, Integer)
    raise ArgumentError, "Missing mcp_server_config_id" if mcp_server_config_id == 0

    return_url = T.let(parts[1] || "", String)

    {
      mcp_server_config_id: mcp_server_config_id,
      return_url: return_url,
    }
  end

  sig { params(mcp_server_config_id: Integer, return_url: T.nilable(String)).returns(String) }
  def self.build(mcp_server_config_id, return_url)
    return_url.present? ? "#{mcp_server_config_id}|#{return_url}" : "#{mcp_server_config_id}"
  end
end
