# typed: true
# frozen_string_literal: true

class GitHubModels::Prompts::Message
  class Role < T::Enum
    enums do
      User = new("user")
      Assistant = new("assistant")
      Tool = new("tool")
      System = new("system")
      Developer = new("developer")
    end
  end

  sig { params(role: String, content: String).void }
  def initialize(role:, content:)
    @role = role
    @content = content
  end

  sig { returns(String) }
  def role
    @role
  end

  sig { returns(String) }
  def content
    @content
  end
end
