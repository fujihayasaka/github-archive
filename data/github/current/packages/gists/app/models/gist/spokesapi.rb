# typed: false
# frozen_string_literal: true

module Gist::SpokesAPI
  include SpokesAPI::ContextDependency

  def spokes_api(timeout: nil)
    if timeout
      return SpokesAPI::Client.for_gist(
        id,
        gist_name: repo_name,
        timeout: timeout,
        context: self.spokes_api_context
      )
    end
    @spokes_api ||= SpokesAPI::Client.for_gist(id, gist_name: repo_name, context: self.spokes_api_context)
  end

  # Public: Find the hash algorithm in use in this repository.
  #
  # Returns a subclass of GitHub::HashAlgorithm.
  def hash_algo
    return @hash_algo if @hash_algo
    @hash_algo = spokes_api.get_repository_metadata[:hash_algo]
  end

  # Public: Set the hash algorithm for use in this gist.
  #
  # The argument must implement GitHub::HashAlgorithm::ClassMethods.
  #
  # This should only be used during gist creation; otherwise, `hash_algo` will
  # return the right thing automatically.
  def hash_algo=(algo)
    @hash_algo = algo
  end
end
