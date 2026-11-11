# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Readme
      module Pages
        module Fetchers
          module NavigationTopicsFetcher
            def fetch_navigation_topics
              Site::Contentful::Readme::Topic.navigation_topics
            end
          end
        end
      end
    end
  end
end
