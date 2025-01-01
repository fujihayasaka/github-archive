# typed: false
# frozen_string_literal: true

module Api::Serializer::StarsDependency
  # Creates a Hash to be serialized to JSON.
  #
  # star    - Star instance
  # options -  Hash
  #
  # Returns a Hash if the Star exists, or nil.
  def star_hash(star, options = {})
    return nil unless star
    options = Api::SerializerOptions.from(options)

    # TODO: Expose Star with timestamps in v4?
    # (see star_hash_with_timestamps and stargazer_hash_with_timestamps below)
    repository_hash(star.starrable, options)
  end

  # Creates a Hash to be serialized to JSON
  #
  # star    - Star instance
  # options - Hash
  #
  # Returns a Hash if the Star exists, or nil.
  def star_hash_with_timestamps(star, options = {})
    return nil unless star
    options = Api::SerializerOptions.from(options)

    {
      starred_at: time(star.created_at),
      repo: repository_hash(star.starrable, options),
    }
  end

  # Creates a Hash to be serialized to JSON
  #
  # star    - Star instance
  # options - Hash
  #
  # Returns a Hash of User info if the Star exists, or nil.
  def stargazer_hash(star, options = {})
    return nil unless star

    user_hash(star.user || User.ghost, content_options(options))
  end

  # Creates a Hash to be serialized to JSON
  #
  # star    - Star instance
  # options - Hash
  #
  # Returns a Hash if the Star exists, or nil.
  def stargazer_hash_with_timestamps(star, options = {})
    return nil unless star

    {
      starred_at: time(star.created_at),
      user: user_hash(star.user || User.ghost, content_options(options)),
    }
  end
end
