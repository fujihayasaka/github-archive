# typed: true
# frozen_string_literal: true

module Stratocaster
  module Filters
    autoload :AppsFilter, "stratocaster/filters/apps_filter"
    autoload :BaseFilter, "stratocaster/filters/base_filter"
    autoload :ConditionalAccessFilter, "stratocaster/filters/conditional_access_filter"
    autoload :DeletedActorsFilter, "stratocaster/filters/deleted_actors_filter"
    autoload :DeletedReposFilter, "stratocaster/filters/deleted_repos_filter"
    autoload :ExternalIdentityFilter, "stratocaster/filters/external_identity_filter"
    autoload :FollowEventsFilter, "stratocaster/filters/follow_events_filter"
    autoload :OrgFollowEventsFilter, "stratocaster/filters/org_follow_events_filter"
    autoload :IgnoredUsersFilter, "stratocaster/filters/ignored_users_filter"
    autoload :IpAllowlistFilter, "stratocaster/filters/ip_allowlist_filter"
    autoload :LabeledEventsFilter, "stratocaster/filters/labeled_events_filter"
    autoload :OauthApplicationFilter, "stratocaster/filters/oauth_application_filter"
    autoload :OrgAllEventTypesFilter, "stratocaster/filters/org_all_event_types_filter"
    autoload :PrivateProfilesFilter, "stratocaster/filters/private_profiles_filter"
    autoload :ReleaseEventsFilter, "stratocaster/filters/release_events_filter"
    autoload :SpamFilter, "stratocaster/filters/spam_filter"
    autoload :SponsorEventsFilter, "stratocaster/filters/sponsor_events_filter"
    autoload :TeamMembersFilter, "stratocaster/filters/team_members_filter"
    autoload :WorkflowEventsFilter, "stratocaster/filters/workflow_events_filter"
    autoload :RetentionFilter, "stratocaster/filters/retention_filter"
  end
end
