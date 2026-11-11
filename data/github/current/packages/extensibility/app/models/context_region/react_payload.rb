# typed: true
# frozen_string_literal: true

module ContextRegion
  class ReactPayload
    # Provide a path resolver lambda/proc to compute Rails route paths for crumbs
    def self.generate(crumb:, path_resolver: nil, current_user: nil, selected_link: nil)
      tab_payload = crumb.tab_payload(user: current_user)

      {
        crumbs: crumb.crumbs.map { |c| crumb_to_hash(c, path_resolver) },
        localNavigation: tab_payload ? tab_payload.tabs : [],
        selectedLink: selected_link,
      }
    end

    def self.crumb_to_hash(crumb, path_resolver)
      crumb_hash = crumb.to_h

      # Compute the path if needed and path resolver is available
      if path_resolver && !crumb_hash[:href] && crumb.path_name
        crumb_hash[:href] = path_resolver.call(crumb.path_name, crumb.path_args)
      end

      crumb_hash
    end
  end
end
