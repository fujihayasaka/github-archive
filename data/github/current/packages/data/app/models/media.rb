# typed: true
# frozen_string_literal: true

module Media
  # This must be the same as what the GitAuth code uses to
  # create the auth token in the first place.
  def self.auth_scope(repo_id, operation, deploy_key_id: nil)
    ["lfs", repo_id, operation, deploy_key_id].compact.join(":")
  end

  # This value is a database ID.
  # It might be missing or empty, in which case we should return nil.
  def self.deploy_key_id_from_env(env)
    id = env["HTTP_GITHUB_DEPLOY_KEY"].to_i
    id == 0 ? nil : id
  end

  # Parse members of the form user:id:login, representing access based on a
  # user's permissions.  Return nil if the member is not of that form.
  def self.user_id_from_member(member)
    type, id = GitHub::Authentication::GitAuth::SignedAuthToken.member(member)
    return nil unless type == "user"
    id
  end

  # Parse members of the form repo:id:nwo, representing access based on a
  # repository's permissions.  Return nil if the member is not of that form.
  def self.repo_id_from_member(member)
    type, id = GitHub::Authentication::GitAuth::SignedAuthToken.member(member)
    return nil unless type == "repo"
    id
  end
end
