# typed: true
# frozen_string_literal: true

module PullRequest::ImageDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PullRequest }

  def async_og_image_url
    async_uri_dependencies.then do |_, repo, _issue|
      next Promise.resolve(nil) unless repo&.show_enhanced_og_image?

      og_image_url
    end
  end

  def og_image_url
    issue = T.must(self.issue)
    repository = T.must(self.repository)

    open_graph = OpenGraph.new(self,
      cache_key_parts: [
        updated_at,
        issue.updated_at,
        repository.name,
        repository.owner_id,
      ]
    )
    open_graph.og_image_url
  end
end
