# typed: true
# frozen_string_literal: true

class UserHovercard
  class GlobalSubject
    include UserHovercard::SubjectDefinition

    define_user_hovercard_context :organizations, ->(user, viewer, descendant_subjects:) do
      # Get a list of all organizations the viewer can see that the user belongs
      # to and bail if there are none we can show
      visible_organizations = user.organizations_visible_to(viewer).filter_spam_for(viewer)
      next if visible_organizations.empty?

      # Figure out what organization we'll be highlighting, and bail if there
      # are none and we're displaying a non-global subject
      related_organizations = descendant_subjects.select { |s| s.is_a?(Organization) }
      related_organizations = visible_organizations.where(id: related_organizations.map(&:id))
      next if related_organizations.empty? && descendant_subjects.any?

      # Make sure the viewer can see these organizations and show the list
      UserHovercard::Contexts::Organizations.new(related: related_organizations,
        all: visible_organizations, user: user)
    end

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :new_user, ->(user, _viewer, descendant_subjects:) do
      if user.joined_in_last_month?
        Hovercard::Contexts::Custom.new("Joined GitHub this month", "rocket")
      end
    end
    # rubocop:enable Lint/UnusedBlockArgument

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :blocks, ->(user, viewer, descendant_subjects:) do
      if user.blocked_by?(viewer)
        UserHovercard::Contexts::Blocks.new(blocked_by_viewer: true, blocking_org: nil)
      end
    end
    # rubocop:enable Lint/UnusedBlockArgument

    define_user_hovercard_context :your_sponsor, ->(user, viewer, descendant_subjects:) do
      if GitHub.sponsors_enabled?
        direct_sponsorship = user.sponsorship_as_sponsor_for(viewer)

        if direct_sponsorship&.active?
          UserHovercard::Contexts::YourSponsor.new(
            private_sponsor: direct_sponsorship.privacy_private?,
            related_org_sponsors: []
          )
        elsif viewer && !descendant_subjects.any? { |subj| subj.is_a?(SponsorsListing) }
          indirect_sponsorships = viewer.indirect_sponsorships_from(user, viewer: viewer)
            .includes(:sponsor)
          sponsoring_orgs = indirect_sponsorships.map(&:sponsor).uniq

          if indirect_sponsorships.any?
            UserHovercard::Contexts::YourSponsor.new(
              private_sponsor: false,
              related_org_sponsors: sponsoring_orgs
            )
          end
        end
      end
    end
  end
end
