# typed: true
# frozen_string_literal: true

class ProfilesController
  class ShowProfileStats
    # Public: Generate tags to be attached to a datadog metric
    # for a user profile page request
    #
    # activity_overview_rendered: Boolean, whether or not activity overview was rendered for this request
    # subject_user: User whose profile is being viewed
    # viewer: User who is viewing the profile
    #
    # Returns array of strings
    def self.tags(activity_overview_rendered:, subject_user:, viewer:, hide_spider_graph: false)
      boolean_tag_values = {
        "activity_overview_rendered" => activity_overview_rendered,
        "subject_user.org_scoped_activity_opt_in_enabled" => true,
        "viewer.org_scoped_activity_opt_in_enabled" => true,
        "viewer_is_site_admin" => viewer.site_admin?,
        "subject_user_is_site_admin" => subject_user.site_admin?,
      }

      # While testing the feature flag, record stats so we can evaluate the
      # performance impact of removing the spider graph.
      if activity_overview_rendered
        boolean_tag_values["spider_graph_rendered"] = !hide_spider_graph
      end

      boolean_tags = boolean_tag_values.map do |tag_prefix, value|
        "#{tag_prefix}:#{value}"
      end

      boolean_tags << "action:show"
    end
  end
end
