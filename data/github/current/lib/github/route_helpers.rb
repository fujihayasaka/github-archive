# typed: false
# frozen_string_literal: true

module GitHub
  # A collection of route helpers to help keep noise down in views
  # and be able to more easily grep/ack for the definitions
  #
  # These should all be prefixed with `gh_`
  module RouteHelpers
    # make sure we expose our route helpers to the views if we get included
    # by a controller
    def self.included(base)
      base.helper_method *instance_methods if base.respond_to? :helper_method
    end

    # Calls the helper method passed, expanding out the nwo params
    # from the model passed
    #
    # helper  - the helper method (symbol) to be called
    # subject - the model instance which we'll use to infer the nwo info from.
    #
    # Returns the return value of the helper method specified, which should be
    # a relative/absolute URL prefixed by the inferred nwo info
    def expand_nwo_from(helper, subject)
      args = case subject
      when Repository, ::Stafftools::Repository
        [subject.owner_display_login, subject]
      when Gist
        # Gist supports anon owners, user_param handles that
        [subject.user_param, subject]
      when Topic
        [subject]
      else
        [subject.repository.owner_display_login, subject.repository, subject]
      end
      send(helper, *args)
    end
  end
end

# require the other route helpers now that our base definition is setup
Dir[File.join(Rails.root, "lib/github/route_helpers/**/*.rb")].each do |helper|
  require helper
end
