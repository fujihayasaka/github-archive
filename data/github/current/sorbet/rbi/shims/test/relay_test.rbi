# typed: true

class GitHubRelayTest
  sig { returns(T.nilable(Integer)) }
  def id; end

  sig { returns(T.nilable(User)) }
  def user; end
end
