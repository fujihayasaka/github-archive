# typed: false
# frozen_string_literal: true

module Api::Serializer::StatsDependency

  # Replaces pre-serialized author information from graph data with the generic version used by the API.
  def contributor_totals_hash(data, options = {})
    return if !data

    data.deep_symbolize_keys.tap do |top_contributor|
      author_info = top_contributor.delete(:author)
      author = User.find_by_login(author_info[:login])
      top_contributor[:author] = simple_user_hash(author, content_options(options))
    end
  end
end
