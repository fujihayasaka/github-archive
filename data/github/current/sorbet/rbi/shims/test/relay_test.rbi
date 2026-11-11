# typed: true

class GitHubRelayTest
  sig { returns(T.nilable(Integer)) }
  def id; end

  sig { returns(T.nilable(Milestone)) }
  def milestone; end
end
