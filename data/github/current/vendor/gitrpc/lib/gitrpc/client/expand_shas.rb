# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Expand an array of short SHAs (of any length, but at least 7 characters)
    # to their full value.
    #
    # Returns a hash of `{ short_sha => full_sha }` for all the SHAs that were
    # found in the repository. SHAs that were not found or that had a different
    # type than `expected_type` will not be included in the hash.
    #
    # sha_list - an Array of SHA strings
    # expected_type - String, expected object type for the SHAs; if nil, all shas
    # will be expanded regardless of their type
    def expand_shas(sha_list, expected_type = nil)
      use_git = self.feature_enabled?(:expand_shas_git)

      if use_git
        send_message(:alternative_expand_shas, sha_list, expected_type)
      else
        science "expand_shas_git_experiment" do |e|
          e.context({ repository_key: self.repository_key, sha_list: sha_list, expected_type: expected_type })
          e.use { send_message(            :expand_shas, sha_list, expected_type) }
          e.try { send_message(:alternative_expand_shas, sha_list, expected_type) }
        end
      end
    end
  end
end
