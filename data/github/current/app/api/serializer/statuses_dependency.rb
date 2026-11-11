# typed: true
# frozen_string_literal: true

module Api::Serializer::StatusesDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  # Creates a hash from a Status to be serialized to JSON. A short representation
  # suitable for sub-resources.
  #
  # status - Status instance
  # options - Hash
  #
  # Returns a Hash if the Status exists, or nil
  def simple_status_hash(status, options = {})
    return nil unless status

    {}.tap do |opts|
      opts[:url] = url("/repos/#{status.repository.name_with_owner_for_api(use: options[:serialize_login])}/statuses/#{status.sha}")
      opts[:avatar_url]  = status_avatar_url(status)
      opts[:id]          = status.id
      opts[:node_id]     = global_id_for(status, options)
      opts[:state]       = status.state
      opts[:description] = status.description
      opts[:target_url]  = status.target_url
      opts[:context]     = status.context
      opts[:created_at]  = time(status.created_at)
      opts[:updated_at]  = time(status.updated_at)
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # status   - Status instance.
  # options -  Hash
  #
  # Returns a Hash if the Status exists, or nil.
  def status_hash(status, options = {})
    options = Api::SerializerOptions.from(options)
    hash = simple_status_hash(status, options)
    return hash if hash.nil?

    hash[:creator] = user_hash(status.creator, content_options(options))
    hash
  end

  # Creates a Hash to be serialized to JSON
  #
  # combined_status - CombinedStatus instance
  # options - Hash
  #
  # Returns a hash if the repo and ref exist, or nil.
  def combined_status_hash(combined_status, options = {})
    return nil unless combined_status

    repo = combined_status.repository
    statuses = combined_status.statuses.map do |status|
      simple_status_hash(status, options)
    end

    {
      state: combined_status.state,
      statuses: statuses,
      sha: combined_status.sha,
      total_count: combined_status.count,
      repository: simple_repository_hash(repo, options),
      commit_url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{combined_status.sha}"),
      url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{combined_status.sha}/status"),
    }
  end

  def status_avatar_url(status)
    if status.oauth_application
      avatar(status.oauth_application)
    elsif status.creator
      avatar(status.creator)
    else
      nil
    end
  end
end
