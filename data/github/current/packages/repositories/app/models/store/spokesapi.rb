# typed: false
# frozen_string_literal: true

module Store::SpokesAPI
  include SpokesAPI::ContextDependency

  def spokes_api(timeout: nil)
    if timeout
      return SpokesAPI::Client.for_store(
        spokes_id,
        timeout: timeout,
        context: self.spokes_api_context
      )
    end
    @spokes_api ||= SpokesAPI::Client.for_store(spokes_id, context: self.spokes_api_context)
  end

  # Public: Find the hash algorithm in use in this repository.
  #
  # Returns a subclass of GitHub::HashAlgorithm.
  def hash_algo
    return @hash_algo if @hash_algo
    @hash_algo = spokes_api.get_repository_metadata[:hash_algo]
  end
end
