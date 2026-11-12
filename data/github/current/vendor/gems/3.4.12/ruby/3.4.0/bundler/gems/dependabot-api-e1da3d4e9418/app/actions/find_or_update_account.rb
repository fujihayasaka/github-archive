# frozen_string_literal: true

# Find an account by github_id and type (org or user), and update its type if it
# does not match with the up to date type from GitHub.
class FindOrUpdateAccount
  # @param github_id [Integer] the user or organizations GitHub ID.
  # @param type [String] the up to date account type, `org` | `user`
  # @return [FindOrUpdateAccount]
  def initialize(github_id:, type:)
    @github_id = github_id
    @type = type
  end

  # @return [Account] the account that was found, possibly updated
  # @raises [ActiveRecord::RecordNotFound] if no account with the given
  # `github_id` was found.
  # @note Users can be upgraded to Organizations, but the other way around is
  # currently not possible. We do nothing to enforce this and assume GitHub will
  # always be up to date.
  def run
    Account.find_by!(
      github_id: github_id,
      account_type: type,
    )
  rescue ActiveRecord::RecordNotFound
    if (account = Account.find_by(github_id: github_id))
      account.update!(account_type: type)
      return account.reload
    end

    raise
  end

  private

  attr_reader :github_id, :type
end
