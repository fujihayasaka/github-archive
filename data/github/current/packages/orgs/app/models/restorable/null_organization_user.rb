# typed: true
# frozen_string_literal: true

# Public: This is a NULL copy of Restorable::OrganizationUser returned when a
# restorable isn't found so that calling code doesn't have to use any
# conditionals and can just treat a restorable as a restorable.
class Restorable
  class NullOrganizationUser
    def self.start(organization, user); end

    def self.continue(organization, user); end

    def self.restorable(organization, user); end

    def save_memberships(memberships); end

    def save_memberships_complete; end

    def save_issue_assignments(issue_assignments); end

    def save_issue_assignments_complete; end

    def save_watched_repositories(watched_repositories); end

    def save_watched_repositories_complete; end

    def save_repository_stars(repository_stars); end

    def save_repository_stars_from_stars(star_entities); end

    def save_repository_stars_complete; end

    def save_repositories(repositories); end

    def save_repositories_complete; end

    def save_custom_email_routings(email); end

    def save_custom_email_routings_complete; end

    def restore(actor: nil); end

    def job_status; end

    def restorable?
      false
    end

    def saving?
      false
    end
  end
end
