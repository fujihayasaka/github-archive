# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Readme
      module Pages
        module Fetchers
          module MoreStoriesFetcher
            def self.oldest_index_to_lookup_for_more_stories
              rand(10)
            end

            def fetch_more_stories_for(story)
              Site::Contentful::Readme::BaseStory.fetch_more_stories_related_to(
                story.slug,
                story_klass: story.class,
                content_type: story.content_type.id,
                take: 3,
                skip: MoreStoriesFetcher.oldest_index_to_lookup_for_more_stories,
              )
            end
          end
        end
      end
    end
  end
end
