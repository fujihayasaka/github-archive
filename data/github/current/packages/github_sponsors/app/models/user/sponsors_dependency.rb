# typed: true
# frozen_string_literal: true

module User::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  ZUORA_PROCESSING_TIME_IN_DAYS = 2
  PREVIEW_SPONSORS_PROFILE_BANNER = "preview_sponsors_profile"

  included do
    T.bind(self, T.class_of(User))

    # Public: CustomerAccount record if this User's sponsorships are being paid for by a separate Customer than the
    # general-purpose `customer_account` (optional).
    has_one :sponsors_customer_account, -> do
      T.bind(self, T.untyped)
      sponsors_purpose
    end, dependent: :destroy, class_name: "CustomerAccount"

    # Public: Customer that pays for this user's sponsorships, if the user has a separate account for paying for their
    # sponsorships compared to general-purpose billing (optional).
    has_one :sponsors_customer, through: :sponsors_customer_account, autosave: true, source: :customer

    has_one :sponsors_patreon_user, inverse_of: :user

    has_one :bulk_sponsorship_tier_selection, inverse_of: :sponsor
    has_one :bulk_sponsorship_import, inverse_of: :sponsor

    # rubocop:todo Rails/InverseOf
    has_many :sponsors_activities, foreign_key: "sponsorable_id", dependent: :destroy
    has_many :sponsors_activity_metrics, foreign_key: "sponsorable_id"
    has_many :sponsors_activities_as_sponsor, class_name: "SponsorsActivity",
      foreign_key: :sponsor_id
    # rubocop:enable Rails/InverseOf

    has_many :repository_sponsorables, dependent: :destroy, foreign_key: "sponsorable_id", inverse_of: :sponsorable

    has_many :sponsorship_repositories_as_sponsor, inverse_of: :sponsor,
      class_name: "SponsorshipRepository", foreign_key: :sponsor_id,
      dependent: :destroy

    has_many :sponsorship_repositories_as_sponsorable, inverse_of: :sponsorable,
      class_name: "SponsorshipRepository", foreign_key: :sponsorable_id

    has_many :potential_sponsorships_as_sponsorable, inverse_of: :potential_sponsorable,
      class_name: "PotentialSponsorship", foreign_key: "potential_sponsorable_id"

    has_many :potential_sponsorships_as_sponsor, inverse_of: :potential_sponsor,
      class_name: "PotentialSponsorship", foreign_key: "potential_sponsor_id"

    has_one :sponsors_plan_subscription, -> do
      T.bind(self, T.untyped)
      sponsors_purpose
    end, class_name: "Billing::PlanSubscription", dependent: :destroy

    # Active and inactive sponsorships where this user/org is the sponsor, either privately or publicly. For an
    # organization, includes those sponsorships this organization gets credit for when the sponsorship is actually
    # paid for by a different organization.
    has_many :sponsorships_as_sponsor, ->(sponsor) do
      T.bind(self, T.untyped)
      if sponsor.organization? && (linked_org_id = sponsor.sponsoring_linked_organization_id)
        unscope(where: :sponsor_id).from_sponsor(sponsor.id).or(Sponsorship.from_sponsor(linked_org_id))
      else
        scoped
      end
    end, class_name: "Sponsorship", foreign_key: :sponsor_id, inverse_of: :sponsor, dependent: :destroy do
      def ranked(for_user:)
        T.bind(self, T.untyped)
        ranked_by_sponsorable(for_user: for_user)
      end
    end

    has_many :sponsorships_as_sponsorable,
      class_name: "Sponsorship",
      inverse_of: :sponsorable,
      foreign_key: :sponsorable_id do
        def ranked(for_user:)
          T.bind(self, T.untyped)
          ranked_by_sponsor(for_user: for_user)
        end
      end

    has_many :active_sponsorships_as_sponsorable, -> do
      T.bind(self, T.untyped)
      active
    end, class_name: "Sponsorship", inverse_of: :sponsorable, foreign_key: :sponsorable_id do
      def ranked(for_user:)
        T.bind(self, T.untyped)
        ranked_by_sponsor(for_user: for_user)
      end
    end

    has_many :active_recurring_sponsorships_as_sponsorable, -> do
      T.bind(self, T.untyped)
      active.recurring
    end, class_name: "Sponsorship", inverse_of: :sponsorable, foreign_key: :sponsorable_id do
      def ranked(for_user:)
        T.bind(self, T.untyped)
        ranked_by_sponsor(for_user: for_user)
      end
    end

    has_many :sponsorship_match_bans_as_sponsorable,
      class_name: "SponsorshipMatchBan",
      foreign_key: "sponsorable_id",
      dependent: :destroy,
      inverse_of: :sponsorable

    has_many :sponsorship_newsletters, foreign_key: :sponsorable_id, inverse_of: :sponsorable

    has_many :sponsors_listing_featured_items, as: :featureable, dependent: :destroy

    has_many :sponsors_invoiced_agreement_signatures_as_signatory, foreign_key: :signatory_id, inverse_of: :signatory,
      class_name: "SponsorsInvoicedAgreementSignature"

    has_one :newest_sponsors_business_tax_identifier, -> { order(created_at: :desc) },
       class_name: "SponsorsBusinessTaxIdentifier",
       dependent: :destroy

    has_one :sponsors_listing_stafftools_metadata, foreign_key: "sponsorable_id", inverse_of: :sponsorable

    has_many :sponsors_business_tax_identifiers, -> { order(created_at: :desc) },
       dependent: :destroy

    has_one :sponsors_listing, foreign_key: :sponsorable_id, dependent: :destroy,
      inverse_of: :sponsorable

    has_many :stripe_connect_accounts, through: :sponsors_listing, inverse_of: :sponsorable, disable_joins: true

    has_one :sponsors_contact_email, through: :sponsors_listing, disable_joins: true,
      class_name: "UserEmail", source: :contact_email

    has_one :approved_sponsors_listing, -> do
      T.bind(self, T.untyped)
      with_approved_state
    end, foreign_key: "sponsorable_id", class_name: "SponsorsListing", inverse_of: :sponsorable

    has_many :invoiced_sponsorship_transfers_as_sponsor,
      class_name: "InvoicedSponsorshipTransfer",
      foreign_key: :sponsor_id,
      dependent: :destroy,
      inverse_of: :sponsor

    # rubocop:todo Rails/InverseOf
    has_one :sponsoring_parent_organization_profile,
      class_name: "OrganizationProfile",
      foreign_key: :sponsoring_linked_organization_id
    # rubocop:enable Rails/InverseOf

    # Public: Indicates if the currently authenticated user is already sponsoring this account.
    #
    # viewer - currently authenticated User, if any
    #
    # Returns a Boolean.
    batch_method :sponsored_by_viewer? do |sponsorables, viewer|
      next Hash.new(false) unless viewer
      results = Promise.all(sponsorables.map { |s| s.async_sponsored_by_viewer?(viewer) }).sync
      sponsorables.zip(results).to_h
    end

    # Public: Indicates if the currently authenticated user is sponsored by this account
    #
    # viewer - currently authenticated User, if any
    #
    # Returns a Boolean
    batch_method :sponsoring_viewer? do |sponsors, viewer|
      promises = sponsors.map do |sponsor|
        sponsor.async_sponsoring_viewer?(viewer, include_private: true)
      end
      results = Promise.all(promises).sync
      sponsors.zip(results).to_h
    end

    # Public: Check if this user has a publicly visible GitHub Sponsors profile page such that they can receive
    # sponsorships.
    #
    # To prevent N+1s when this method is called on a list of User records,
    # prefill it this way:
    #
    # Execute few queries to preload, such as in a controller action:
    #     GitHub::PrefillAssociations.prefill_batch_method(users, :sponsorable?)
    #
    #     users.each do |user|
    #       # Method is preloaded and memoized - no queries are executed here!
    #       user.sponsorable?
    #     end
    #
    # Returns a Boolean.
    batch_method :sponsorable? do |sponsorables|
      results = Promise.all(sponsorables.map(&:async_sponsorable?)).sync
      sponsorables.zip(results).to_h
    end

    # Public: Get sponsorships where this user is the one funding the sponsorship and the maintainer who is receiving
    # the funds still has a published Sponsors profile. Includes both public and private sponsorships. Includes
    # sponsorships from the linked organization, for organization sponsors.
    #
    # scope - optional ActiveRecord::Relation for Sponsorship to further limit the returned sponsorships,
    #         e.g., `Sponsorship.privacy_public`
    #
    # Examples:
    #
    #   # To prevent N+1s when this method is called on a list of User records,
    #   # prefill it this way:
    #
    #   # Execute few queries to preload, such as in a controller action:
    #   GitHub::PrefillAssociations.prefill_batch_method(sponsors, :active_sponsorships_as_sponsor)
    #   GitHub::PrefillAssociations.prefill_batch_method(sponsors, :active_sponsorships_as_sponsor, {
    #     scope: Sponsorship.privacy_public,
    #   })
    #
    #   sponsors.each do |sponsor|
    #     # Methods are preloaded and memoized - no queries are executed here!
    #     sponsor.active_sponsorships_as_sponsor
    #     sponsor.active_sponsorships_as_sponsor(scope: Sponsorship.privacy_public)
    #   end
    #
    # Returns an Array of Sponsorship.
    batch_method :active_sponsorships_as_sponsor do |*args|
      sponsors = args.shift
      scope = (args.shift || {})[:scope]

      sponsor_ids = sponsors.map(&:id).compact
      active_sponsorships_by_sponsor_id = {}
      linked_org_ids_by_sponsor_id = {}

      org_sponsor_ids = sponsors.select(&:organization?).map(&:id).compact
      if org_sponsor_ids.any?
        linked_org_ids_by_sponsor_id = OrganizationProfile.for_organization(org_sponsor_ids)
          .pluck(:organization_id, :sponsoring_linked_organization_id)
          .to_h
      end

      if sponsor_ids.any?
        base_query = Sponsorship.active.listing_approved
        base_query = base_query.merge(scope) if scope
        linked_org_ids = linked_org_ids_by_sponsor_id.values.compact

        sponsorships = base_query.from_sponsor(sponsor_ids.first)
        (sponsor_ids + linked_org_ids).drop(1).each do |sponsor_id|
          sponsorships = sponsorships.or(base_query.from_sponsor(sponsor_id))
        end

        active_sponsorships_by_sponsor_id = sponsorships.each_with_object({}) do |sponsorship, hash|
          hash[sponsorship.sponsor_id] ||= []
          hash[sponsorship.sponsor_id] << sponsorship
        end
      end

      sponsors.each_with_object({}) do |sponsor, hash|
        linked_org_id = linked_org_ids_by_sponsor_id[sponsor.id]
        sponsorships_for_sponsor = active_sponsorships_by_sponsor_id[sponsor.id] || []
        sponsorships_for_sponsor.concat(active_sponsorships_by_sponsor_id[linked_org_id] || []) if linked_org_id
        hash[sponsor] = sponsorships_for_sponsor
      end
    end
  end

  class_methods do

    # Public: Get a list of users and organizations who have a public GitHub Sponsors profile.
    #
    # logins - an Array of String logins for users and orgs to check for sponsorability
    sig { params(logins: T.any(String, T::Array[String])).returns(T::Array[GitHubSponsors::Types::Sponsorable]) }
    def sponsorable_users_from_logins(logins)
      SponsorsListing
        .with_approved_state
        .with_sponsorable_logins(logins)
        .select(:sponsorable_id, :state)
        .includes(:sponsorable)
        .map(&:sponsorable)
        .compact
    end

    # Public: Filter a list of User and Organization IDs to just those that can be sponsored
    # by the given viewer.
    #
    # user_ids - list of User and Organization database IDs
    # viewer - currently authenticated User
    # limit - how many SponsorsListing records to check; pass -1 for no limit
    # include_viewer - by default, if the given viewer is one of the sponsorable users,
    #                  their ID will be omitted from the result; pass true to include
    #                  the viewer when they're sponsorable
    #
    # Returns a Set of Integer database IDs for Users and Organizations.
    sig do
      params(
        user_ids: T::Array[Integer],
        viewer: T.nilable(User),
        limit: Integer,
        include_viewer: T::Boolean,
      ).returns(T::Set[Integer])
    end
    def sponsorable_user_ids_from(user_ids, viewer: nil, limit: 1_000, include_viewer: false)
      return Set.new if user_ids.empty?

      spammy_or_blocking_viewer_sponsorable_ids = User.spammy_or_blocking(viewer).where(id: user_ids).pluck(:id)
      listings = SponsorsListing.with_approved_state
        .for_sponsorable_user_or_org(user_ids)
        .without_sponsorable_users(spammy_or_blocking_viewer_sponsorable_ids)
      listings = listings.limit(limit) if limit > 0

      # Can't sponsor yourself, so don't include your own ID in the results:
      listings = listings.without_sponsorable_users(viewer) if viewer && !include_viewer

      Set.new(listings.pluck(:sponsorable_id))
    end

    # Public: Sort a list of users, in a stable way, by how many sponsors they have -- that is, by how many active
    # sponsorships they are receiving. Preserves the order of the given list of users when two users have the same
    # number of sponsors.
    #
    # Returns a sorted Array of the given users and orgs in ascending order by sponsor count. That is, those
    # with the fewest sponsors will be first.
    sig do
      params(
        users: T::Array[GitHubSponsors::Types::Sponsorable]
      ).returns(T::Array[GitHubSponsors::Types::Sponsorable])
    end
    def sort_by_sponsor_count(users)
      user_ids = users.map(&:id).uniq
      # Fine to include private sponsors regardless of viewer because it's just the identity of the sponsor
      # that is kept private, not the fact that there is a sponsorship at all:
      sponsor_counts_by_user_id = UserMetadata.where(user_id: user_ids)
        .pluck(:user_id, :sponsors_public_and_private_count).to_h
      sorted_users_and_indices = users.each_with_index.sort_by do |user, index|
        sponsor_count = [sponsor_counts_by_user_id[user.id], 0].compact.max
        [sponsor_count, index]
      end
      sorted_users_and_indices.map(&:first)
    end

    # Public: Sort a list of users and organizations based on when their GitHub Sponsors profile page became publicly
    # available.
    sig do
      params(
        users: T::Array[GitHubSponsors::Types::Sponsorable]
      ).returns(T::Array[GitHubSponsors::Types::Sponsorable])
    end
    def sort_by_sponsors_profile_publish_date(users)
      GitHub::PrefillAssociations.prefill_associations(users, :sponsors_listing)
      sponsors_profile_publish_dates_by_sponsorable_id = users
        .map { |user| [user.id, user.sponsors_listing&.published_at] }
        .to_h
      now = Time.now
      sorted_users_and_indices = users.each_with_index.sort_by do |user, index|
        publish_date = sponsors_profile_publish_dates_by_sponsorable_id[user.id]
        [publish_date || now, index]
      end
      sorted_users_and_indices.map(&:first)
    end
  end

  # Public: Is this user allowed to load the Explore Sponsors results for the specified organization?
  sig { params(org: T.nilable(GitHubSponsors::Types::Sponsor)).returns(T::Boolean) }
  def can_load_sponsorable_dependencies_for?(org)
    return false unless user?
    return false unless org&.organization?
    T.cast(org, Organization).member?(self) || T.cast(org, Organization).billing_manager?(T.cast(self, User)) ||
      can_admin_sponsors_listings?
  end

  # Public: Get a chainable Rails scope for sponsorships where this user or organization is the one funding the
  # sponsorship and the maintainer who is receiving the funds still has a published Sponsors profile. Includes both
  # public and private sponsorships as well as linked organization sponsorships.
  #
  # If you want the Sponsorship records, particularly for many different sponsors, see the
  # #active_sponsorships_as_sponsor batch method instead.
  #
  # Returns an ActiveRecord::Relation of Sponsorship.
  sig { returns ActiveRecord::Relation }
  def active_sponsorships_as_sponsor_relation
    sponsorships_as_sponsor.active.listing_approved
  end

  # Public: Emit a Hydro event to mark sponsorships as paid from this user to maintainers owning the given tiers.
  #
  # sponsors_tiers - an Array of SponsorsTier records for the sponsorships that were paid for
  sig { params(sponsors_tiers: T::Array[SponsorsTier]).void }
  def instrument_sponsorship_payment_complete(sponsors_tiers:)
    return if sponsors_tiers.empty? || !GitHub.sponsors_enabled?

    sponsors_tiers_by_listing_id = sponsors_tiers.each_with_object({}) do |tier, hash|
      hash[tier.sponsors_listing_id] = tier
    end
    sponsorships = sponsorships_for_instrument_payment_complete(sponsors_tiers)
    bulk_tiers_set = payment_incomplete_bulk_sponsorship_tier_ids
    payment_complete_tiers_for_bulk_sonsorship = Array.new

    sponsorships.each do |sponsorship|
      tier = sponsors_tiers_by_listing_id[sponsorship.sponsors_listing_id]
      via_bulk_sponsorship = bulk_tiers_set.include?(tier.id)

      sponsorship.instrument_payment_complete(tier_paid: tier, via_bulk_sponsorship: via_bulk_sponsorship)

      payment_complete_tiers_for_bulk_sonsorship << tier if via_bulk_sponsorship

      # If the active sponsorship is for the tier that was just paid for, update the `paid_at` timestamp
      # so that we can accurately tell if this was the first payment for the sponsorship:
      if sponsorship.tier == tier
        sponsorship.touch(:paid_at)
      end
    end

    send_now_sponsoring_via_bulk_sponsorship_email(payment_complete_tiers_for_bulk_sonsorship)

    payment_complete_tier_ids_for_bulk_sonsorship = payment_complete_tiers_for_bulk_sonsorship.map(&:id).to_set
    remove_tiers_from_bulk_sponsorship_event(payment_complete_tier_ids_for_bulk_sonsorship)
  end

  # Public: Whether this user is actively sponsoring someone. Only includes
  # one-time payments if they were made in the last 30 days. Includes all
  # active recurring sponsorships.
  sig { returns T::Boolean }
  def actively_sponsoring?
    return @is_actively_sponsoring if defined?(@is_actively_sponsoring)
    @is_actively_sponsoring = active_sponsorships_as_sponsor_relation.exists?
  end

  sig { returns T::Boolean }
  def sponsors_supported_time_zone?
    time_zone_name.present? && Sponsors::TimeZone.supported_names.include?(time_zone_name)
  end

  # Public: Is this user/organization one such that they're likely to be accepted into Sponsors?
  sig { returns T::Boolean }
  def eligible_for_nudging_to_sign_up_for_sponsors?
    return false unless GitHub.sponsors_enabled?
    return false unless user? || organization?
    return false if created_at && T.must(created_at).after?(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago)
    return false if spammy? || suspended?
    return false if user? && !sponsors_supported_time_zone?
    return false unless SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
    return false if sponsors_listing && !T.must(sponsors_listing).draft?
    return false if has_sdn_auto_sponsorable_restrictions?
    return false if public_repositories.where(parent_id: nil).empty?
    return false if public_contribution_count_for_sponsors < 1
    true
  end

  sig { returns Integer }
  def public_contribution_count_for_sponsors
    return @public_contribution_count_for_sponsors if @public_contribution_count_for_sponsors

    @public_contribution_count_for_sponsors = if user?
      contribution_classes = [
        Contribution::CreatedCommit,
        Contribution::CreatedIssue,
        Contribution::CreatedPullRequest,
        Contribution::CreatedPullRequestReview,
      ]
      accessor = Contribution::Accessor.new(
        user: self,
        viewer: nil,
        contribution_classes: contribution_classes,
        date_range: 1.year.ago.to_date..Date.current,
        organization_id: nil,
        skip_restricted: true,
      )
      accessor.counts_by_class_name.values.sum
    else
      0
    end
  end

  # Public: Whether this user is actively being sponsored by someone else.
  # Only includes one-time payments if they were made in the last 30 days.
  # Includes all active recurring sponsorships.
  sig { returns T::Boolean }
  def actively_being_sponsored?
    active_sponsorships_as_sponsorable.exists?
  end

  # Public: Whether this sponsorable has an approved Sponsors listing or has active sponsorships.
  sig { returns T::Boolean }
  def active_sponsors_account?
    return false if sponsors_listing.blank?
    return true unless T.must(sponsors_listing).disabled?
    return true if actively_being_sponsored?

    false
  end

  # Public: Get a list of IDs of repositories owned by this user, visible to the specified viewer, that are
  # important somehow to this user and are ones that we think the user would be interested in supporting the
  # dependencies of.
  #
  # viewer - currently authenticated User or nil
  #
  # Returns an Array of Integer Repository IDs.
  sig { params(viewer: T.nilable(User)).returns(T::Array[Integer]) }
  def repository_ids_to_check_for_sponsorable_dependencies(viewer:)
    @repository_ids_to_check_for_sponsorable_dependencies_by_viewer_key ||= {}
    viewer_key = viewer ? viewer.id : "none"
    if @repository_ids_to_check_for_sponsorable_dependencies_by_viewer_key.key?(viewer_key)
      return @repository_ids_to_check_for_sponsorable_dependencies_by_viewer_key[viewer_key]
    end

    repositories_scope = repositories.not_archived_scope

    # Ensure the repositories we check for dependencies are ones that the viewer can see:
    if !viewer
      repositories_scope = repositories_scope.public_scope
    elsif !adminable_by?(viewer)
      all_private_repo_ids = repositories_scope.private_scope.distinct.pluck(:id)
      visible_private_repo_ids = viewer.associated_repository_ids(repository_ids: all_private_repo_ids,
        including: [:direct, :indirect], organization: organization? ? self : nil)
      repositories_scope = repositories_scope.public_scope.or(repositories_scope.where(id: visible_private_repo_ids))
    end

    @repository_ids_to_check_for_sponsorable_dependencies_by_viewer_key[viewer_key] = repositories_scope
      .recently_updated # TODO: factor popularity/importance into sort order
      .limit(Repository::OwnerDependenciesLoader::MAX_REPOSITORY_IDS)
      .distinct
      .pluck(:id)
  end

  # Public: Get the IDs of users and organizations that are both sponsorable and are responsible for this user's
  # direct dependencies, grouped by dependency.
  #
  # viewer - the currently authenticated User, if any
  #
  # Returns a Hash where the keys are Repository IDs (the direct dependencies this user/org has) and the values are
  # an Array of Integer User and Organization IDs (the sponsorables that represent that dependency, either because
  # they own the dependency or they're in a funding file for the dependency).
  sig { params(viewer: T.nilable(User)).returns(T::Hash[Integer, T::Array[Integer]]) }
  def direct_dependency_sponsorable_ids_by_dependency_id(viewer:)
    return {} unless GitHub.sponsors_enabled?

    @direct_dependency_sponsorable_ids_by_dependency_id_by_viewer_id ||= {}
    viewer_id = viewer ? viewer.id : "none"
    if @direct_dependency_sponsorable_ids_by_dependency_id_by_viewer_id.key?(viewer_id)
      return @direct_dependency_sponsorable_ids_by_dependency_id_by_viewer_id[viewer_id]
    end

    loader = Repository::OwnerDependenciesLoader.new(
      public_only: false, # because providing an explicit list of visible repos to check
      direct_only: true,
      owner_id: id,
      package_managers: [],
      sort_by: nil,
      repository_ids: repository_ids_to_check_for_sponsorable_dependencies(viewer: viewer),
      viewer: viewer,
    )
    result = loader.async_dependencies(scope: Repository.sponsorable).sync
    dependency_ids = result.dependency_ids
    repo_sponsorables = RepositorySponsorable.for_repository(dependency_ids).distinct
      .select(:repository_id, :sponsorable_id)

    hash_for_viewer = repo_sponsorables.each_with_object({}) do |repo_sponsorable, hash|
      dependency_id = repo_sponsorable.repository_id
      hash[dependency_id] ||= []
      hash[dependency_id] << repo_sponsorable.sponsorable_id
    end

    @direct_dependency_sponsorable_ids_by_dependency_id_by_viewer_id[viewer_id] = hash_for_viewer
  end

  # Public: Get a count of how many of this user's direct dependencies they are currently sponsoring. A dependency
  # is considered sponsored if the viewer is sponsoring any of the sponsorable users/orgs associated with the
  # dependency, e.g., the owner of the dependency or someone specified in a funding.yml for the dependency.
  #
  # viewer - the currently authenticated User, if any
  sig { params(viewer: T.nilable(User)).returns(Integer) }
  def total_direct_dependencies_sponsored(viewer:)
    return 0 unless GitHub.sponsors_enabled?

    sponsorable_ids_by_dependency_id = direct_dependency_sponsorable_ids_by_dependency_id(viewer: viewer)
    return 0 if sponsorable_ids_by_dependency_id.empty?

    sponsorable_ids = sponsorable_ids_by_dependency_id.values.flatten.uniq
    sponsored_sponsorable_ids = T.unsafe(active_sponsorships_as_sponsor_relation)
      .with_user_or_org_sponsorable(sponsorable_ids)
      .sponsor_visible_to(viewer).distinct.pluck(:sponsorable_id).to_set
    sponsored_pairs = sponsorable_ids_by_dependency_id.select do |_, sponsorable_ids|
      sponsorable_ids.any? { |sponsorable_id| sponsored_sponsorable_ids.include?(sponsorable_id) }
    end
    sponsored_pairs.size
  end

  # Public: Get a count of how many of this user's direct dependencies could be sponsored. A dependency
  # is considered sponsorable if there is any sponsorable users/orgs associated with the
  # dependency, e.g., the owner of the dependency or someone specified in a funding.yml for the dependency.
  #
  # viewer - the currently authenticated User, if any
  sig { params(viewer: T.nilable(User)).returns(Integer) }
  def total_direct_dependencies_sponsorable(viewer:)
    sponsorable_ids_by_dependency_id = direct_dependency_sponsorable_ids_by_dependency_id(viewer: viewer)
    # Count the keys, not how many unique sponsorable IDs there are, because we want to know how many dependencies
    # can be sponsored:
    sponsorable_ids_by_dependency_id.size
  end

  # Public: Get linked organization IDs for the organizations this user belongs to or is billing manager of.
  # These linked orgs are ones whose private sponsorships should be visible to the user.
  #
  # Returns an Array of Integer Organization IDs.
  sig { returns(T::Array[Integer]) }
  def member_or_billing_manager_linked_organization_sponsor_ids
    @member_or_billing_manager_linked_organization_sponsor_ids ||= begin
      org_ids = member_or_billing_manager_organization_ids
      if org_ids.any?
        OrganizationProfile.for_organization(org_ids).pluck(:sponsoring_linked_organization_id)
      else
        []
      end
    end
  end

  sig { returns T.nilable(T::Boolean) }
  def banned_from_sponsors?
    sponsors_listing&.banned?
  end

  # Public: Boolean if a user has had Sponsorship subscriptions rolled back
  sig { returns T::Boolean }
  def has_sponsorship_rollback?
    notices_for_dashboard.include?("sponsorship_rollback")
  end

  # Public: Set the Sponsorship rollback notification setting for a user.
  sig { void }
  def set_sponsorship_rollback_notification
    activate_notice(:sponsorship_rollback) # Makes rollback an active notice for this user
    reset_notice(:sponsorship_rollback)    # Clears any previous dismissal by this user

    GlobalNoticeNext.new(viewer: self).set_notice(:sponsorship_rollback)
  end

  # Public: Can the given actor enroll this user/org in the GitHub Sponsors program?
  sig { params(actor: T.nilable(User)).returns T::Boolean }
  def can_be_enrolled_in_sponsors_by?(actor)
    return false unless actor
    return false if spammy?

    is_sponsors_admin = actor.can_admin_sponsors_listings?
    return false if !is_sponsors_admin && banned_from_sponsors?

    needs_verified_email = user? && should_verify_email?
    return false if needs_verified_email

    is_sponsors_admin || adminable_by?(actor)
  end

  # Public: Get the email address this user/org would like to be contacted at regarding their GitHub Sponsors listing.
  sig { returns T.nilable(String) }
  def sponsors_listing_email
    sponsors_listing&.contact_email_address
  end

  # Public: Is this sponsorable eligible for stripe connect?
  sig { returns T.nilable(T::Boolean) }
  def sponsors_stripe_eligible?
    sponsors_listing&.eligible_for_stripe_connect?
  end

  # Public: Does the sponsorable have room to add another Stripe Connect account for their
  # Sponsors listing?
  sig { returns T::Boolean }
  def within_sponsors_stripe_account_limit?
    return true unless sponsors_listing
    T.must(sponsors_listing).within_stripe_account_limit?
  end

  # Public: Returns this User's subscription items that have a Sponsors Tier as their subscribable
  # from all plan subscriptions
  sig { returns ActiveRecord::Relation }
  def sponsors_and_general_plan_subscription_items
    Billing::SubscriptionItem.for_sponsors_tiers.joins(:plan_subscription)
      .merge(Billing::PlanSubscription.for_user(self))
  end

  # Public: Are Stripe transfers enabled for this user's Sponsors account?
  sig { returns T.nilable(T::Boolean) }
  def sponsors_stripe_transfers_enabled?
    sponsors_listing&.stripe_transfers_enabled?
  end

  # Public: Get the account ID for the Stripe account this user uses for GitHub Sponsors,
  # either for their own personal Stripe account for the Stripe account of the fiscal host
  # they use.
  sig { returns T.nilable(String) }
  def sponsors_stripe_transfer_account_id
    sponsors_listing&.stripe_transfer_account_id
  end

  # Public: Returns the Stripe business type for this user.
  #
  # Returns either "individual" or "company".
  sig { returns String }
  def sponsors_stripe_business_type
    if organization?
      Billing::StripeConnect::Account::BUSINESS_TYPE_COMPANY
    else
      Billing::StripeConnect::Account::BUSINESS_TYPE_INDIVIDUAL
    end
  end

  # Public: Return the Sponsors membership's billing country if it has one.
  sig { returns T.nilable(String) }
  def sponsors_billing_country
    sponsors_listing&.billing_country
  end

  # Public: Return the Sponsors membership's country of residence if it has one.
  sig { returns T.nilable(String) }
  def sponsors_country_of_residence
    sponsors_listing&.country_of_residence
  end

  # Public: Has this account been accepted into the Sponsors program?
  sig { returns T::Boolean }
  def sponsors_program_member?
    return false unless GitHub.sponsors_enabled?
    return false unless sponsors_listing
    T.must(sponsors_listing).accepted_into_sponsors?
  end

  # Public: Is this user or organization on the waitlist to join GitHub Sponsors?
  sig { returns T.nilable(T::Boolean) }
  def sponsors_waitlisted?
    sponsors_listing&.waitlisted?
  end

  sig { returns T.nilable(T::Boolean) }
  def sponsors_featured_disabled?
    sponsors_listing&.featured_disabled?
  end

  sig { returns T.nilable(String) }
  def sponsors_featured_description
    sponsors_listing&.featured_description
  end

  sig { returns T.nilable(String) }
  def sponsors_short_description_html
    sponsors_listing&.short_description_html
  end

  sig { returns T.nilable(String) }
  def sponsors_bio
    sponsors_featured_description || T.unsafe(self).profile_bio
  end

  sig { returns T.nilable(String) }
  def sponsors_bio_html
    sponsors_short_description_html.presence || T.unsafe(self).profile_bio_html.presence
  end

  # Public: Get the name and address of the Zuora customer who is listed as the billing contact for the sponsors
  #         customer.
  sig { returns T.nilable(Sponsors::BillingContactResult) }
  def sponsors_billing_contact
    return @sponsors_billing_contact if defined?(@sponsors_billing_contact)
    @sponsors_billing_contact = sponsors_customer&.zuora_billing_contact
  end

  sig { returns ActiveRecord::Relation }
  def possible_sponsors_emails
    return UserEmail.none unless user?
    emails.user_entered_emails.verified
  end

  sig { void }
  def synchronize_search_indices_for_sponsors
    synchronize_search_index
    repositories.each(&:synchronize_search_index)
  end

  # Public: Indicates if this account is eligible to be sponsored.
  sig { returns Promise[T::Boolean] }
  def async_sponsorable?
    return Promise.resolve(T.let(false, T::Boolean)) unless GitHub.sponsors_enabled?
    async_sponsors_listing.then do |listing|
      !!listing&.approved?
    end
  end

  # Public: Indicates if an actor is able to sponsor this account. Will return true for a nil actor when this user/org
  # has a public Sponsors profile.
  #
  # actor - the User or Organization that would be the sponsor, or nil
  sig { params(actor: T.nilable(GitHubSponsors::Types::Sponsor)).returns T::Boolean }
  def sponsorable_by?(actor)
    async_sponsorable_by?(actor).sync
  end

  # Public: Indicates if an actor is able to sponsor this account. Will return true for a nil actor when this user/org
  # has a public Sponsors profile.
  #
  # actor - the User or Organization that would be the sponsor, or nil
  sig { params(actor: T.nilable(GitHubSponsors::Types::Sponsor)).returns Promise[T::Boolean] }
  def async_sponsorable_by?(actor)
    return Promise.resolve(T.let(false, T::Boolean)) unless GitHub.sponsors_enabled?
    return Promise.resolve(T.let(false, T::Boolean)) if self == actor

    async_sponsorable?.then do |is_sponsorable|
      next false unless is_sponsorable
      next true if actor.nil?

      async_blocking?(actor).then do |is_maintainer_blocking_actor|
        next false if is_maintainer_blocking_actor

        # If they've never been a sponsor for this user, the actor can sponsor now.
        sponsorship = actor.sponsorship_as_sponsor_for(T.cast(self, User))
        next true unless sponsorship

        sponsorship.async_one_time_payment?.then do |is_one_time_payment|
          if is_one_time_payment
            # Check if the actor currently has a locked sponsorship for this user, implying
            # they made a one-time payment that's still processing. If such exists, they
            # can't yet re-sponsor this user.
            !sponsorship.locked?
          else
            # If the actor has been a sponsor of this user in the past but their recurring
            # sponsorship was cancelled, they can re-sponsor now.
            !sponsorship.active?
          end
        end
      end
    end
  end

  # Public: indicates if a user has an active recurring sponsorship as a sponsor.
  sig { returns T::Boolean }
  def actively_recurring_sponsor?
    T.unsafe(active_sponsorships_as_sponsor_relation).recurring.any?
  end

  # Public: Indicates if a user has an active public sponsorships as a sponsor.
  sig { returns T::Boolean }
  def public_github_sponsor?
    T.unsafe(active_sponsorships_as_sponsor_relation).privacy_public.any?
  end

  # Public: Get sponsorships where this user/org is being sponsored indirectly by the
  # given user. Indirect sponsorship means the given user belongs to an organization
  # that is sponsoring this user/org, and the given user's membership to that
  # sponsoring org is visible to the specified viewer.
  #
  # viewer - the currently authenticated User; used to determine which organizations
  #          should be considered, based on membership visibility for this viewer
  #
  # Returns a Sponsorship ActiveRecord::Relation.
  sig do
    params(
      sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
      viewer: T.nilable(User)
    ).returns(ActiveRecord::Relation)
  end
  def indirect_sponsorships_from(sponsor, viewer:)
    return Sponsorship.none unless sponsor
    return Sponsorship.none unless GitHub.sponsors_enabled?

    sponsors_org_ids = sponsor.organization_ids_visible_to(viewer)
    sponsorships = sponsorships_as_sponsorable.active.where(sponsor_id: sponsors_org_ids)

    # Unless the given viewer is part of the sponsorship, we should
    # restrict sponsorships to only those publicly visible:
    unless viewer == sponsor || viewer == self
      sponsorships = sponsorships.privacy_public
    end

    sponsorships
  end

  # Public: Indicates if the currently authenticated user is already sponsoring this account.
  #
  # viewer - currently authenticated User, if any
  sig { params(viewer: T.nilable(User)).returns Promise[T::Boolean] }
  def async_sponsored_by_viewer?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer&.persisted?
    return Promise.resolve(T.let(false, T::Boolean)) if viewer == self # self-sponsorship is not allowed
    async_sponsor_exists_and_is_visible_to?(T.must(viewer.id), viewer: viewer)
  end

  # Public: Indicates if the currently authenticated user is sponsored by this account
  #
  # viewer - currently authenticated User, if any
  sig { params(viewer: T.nilable(User), include_private: T::Boolean).returns Promise[T::Boolean] }
  def async_sponsoring_viewer?(viewer, include_private: false)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer
    return Promise.resolve(T.let(false, T::Boolean)) if viewer == self

    Platform::Loaders::IsSponsorCheck.load(
      sponsorable_id: viewer.id,
      sponsor_id: self.id,
      include_private: include_private
    )
  end

  # Public: Indicates if the specified user/org is already sponsoring this account, and
  # if the currently authenticated user is allowed to know this.
  #
  # sponsor_id - User or Organization or their ID
  # viewer - currently authenticated User, if any
  sig do
    params(sponsor_id: T.any(Integer, GitHubSponsors::Types::Sponsor), viewer: T.nilable(User)).returns T::Boolean
  end
  def sponsor_exists_and_is_visible_to?(sponsor_id, viewer:)
    active_sponsorships_as_sponsorable.listing_approved.sponsor_visible_to(viewer).from_sponsor(sponsor_id).any?
  end

  # Public: Indicates if the specified user/org(s) are already sponsoring this account, and
  # if the currently authenticated user is allowed to know this. Also considers if the
  # sponsorship was a one-time payment and, if so, how long ago it was made.
  #
  # sponsor_ids - User or Organization ID, or an Array of them
  # viewer - currently authenticated User, if any
  # tier_ids - a SponsorsTier ID or Array of IDs to check for sponsorships using those tiers specifically; if omitted,
  #            sponsorships at any tier will be considered (default)
  #
  # Returns a Promise that resolves to a Boolean.
  sig do
    params(
      sponsor_ids: T.any(Integer, T::Array[Integer]),
      viewer: T.nilable(User),
      tier_ids: T.nilable(T.any(Integer, T::Array[Integer]))
    ).returns(Promise[T::Boolean])
  end
  def async_sponsor_exists_and_is_visible_to?(sponsor_ids, viewer:, tier_ids: nil)
    return Promise.resolve(T.let(false, T::Boolean)) unless sponsor_ids.present?

    Platform::Loaders::IsSponsoringCheck.load(
      sponsor_id: sponsor_ids,
      sponsorable_id: id,
      viewer: viewer,
      tier_ids: tier_ids,
    )
  end

  # Public: Did this sponsor make a one-time payment to a given sponsorable in the last 2 days?
  #
  # Used to tell if Zuora may still be processing the most recent one-time payment.
  #
  # Returns a Boolean
  def processing_one_time_payment_to?(sponsorable)
    !!last_one_time_payment_to(sponsorable)&.timestamp&.after?(ZUORA_PROCESSING_TIME_IN_DAYS.days.ago)
  end

  # Public: the most recent SponsorsActivity object that represents a one-time payment made from this sponsor to a
  #         given sponsorable.
  #
  # Returns a SponsorsActivity or nil
  def last_one_time_payment_to(sponsorable)
    sponsors_activities_as_sponsor.for_sponsorable(sponsorable).is_new_sponsorship.one_time.by_timestamp.first
  end

  # Public: If the user is or has been a sponsor for the given maintainer, returns the corresponding sponsorship.
  #
  # sponsorable - a User or Organization to check for a received sponsorship from this user/org
  sig { params(sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable)).returns(T.nilable(Sponsorship)) }
  def sponsorship_as_sponsor_for(sponsorable)
    return unless sponsorable
    sponsorships_as_sponsor.find_by(sponsorable: sponsorable)
  end

  # Public: Cancel sponsorships between this user and a specified other user.
  #
  # reason - Symbol from Sponsorship::InstrumentationDependency::HYDRO_CANCELLATION_REASONS representing
  #   why the sponsorship is being cancelled
  #
  # Returns a Boolean indicating successful cancellation of all sponsorships from this user to the other user,
  # or from the other user to this user.
  sig do
    params(
      other_user: T.any(GitHubSponsors::Types::Sponsorable, GitHubSponsors::Types::Sponsor),
      actor: User,
      reason: T.nilable(Symbol),
    ).returns(T::Boolean)
  end
  def cancel_sponsorships_from_and_to(other_user, actor:, reason: nil)
    return true if self == other_user # can't self-sponsor so nothing to do

    base_query = Sponsorship.active
    sponsorships_to_cancel = base_query.from_sponsor(self).with_user_or_org_sponsorable(other_user)
      .or(base_query.from_sponsor(other_user).with_user_or_org_sponsorable(self))

    successes = []
    sponsorships_to_cancel.each do |sponsorship|
      result = sponsorship.cancel(actor: actor, reason: reason, force: true)
      successes << result.success
    end
    successes.all?
  end

  sig { params(actor: User, reason: Symbol).returns(T::Boolean) }
  def cancel_all_sponsorships(actor:, reason:)
    sponsorships_to_cancel = T.let(active_sponsorships_as_sponsor_relation
      .includes(:subscription_item, :invoiced_sponsorship_transfer), T::Enumerable[Sponsorship])

    successes = []
    sponsorships_to_cancel.each do |sponsorship|
      result = sponsorship.cancel(actor: actor, reason: reason, force: true)
      successes << result.success
    end

    successes.all?
  end

  # Public: If the user is or has been a sponsor for the given maintainer, returns the corresponding sponsorship.
  #
  # sponsorable - a User or Organization to check for a received sponsorship from this user/org
  sig { params(sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable)).returns(Promise[T.nilable(Sponsorship)]) }
  def async_sponsorship_as_sponsor_for(sponsorable)
    return Promise.resolve(T.let(nil, T.nilable(Sponsorship))) unless sponsorable
    if organization?
      T.cast(self, Organization).async_organization_profile.then do
        sponsorship_as_sponsor_for(sponsorable)
      end
    else
      Promise.resolve(sponsorship_as_sponsor_for(sponsorable))
    end
  end

  # Public: The total monthly amount pledged in dollars.
  sig { returns Billing::Money }
  def total_monthly_pledged_in_dollars
    return Billing::Money.zero unless sponsors_listing
    T.must(sponsors_listing).total_monthly_pledged_in_dollars
  end

  # Public: The total monthly amount pledged for all active recurring sponsorships if visible
  # to the viewer.
  #
  # viewer - currently authenticated User or nil
  #
  # Returns a Billing::Money. $0 can also indicate the viewer is not allowed to see the actual amount.
  sig { params(viewer: T.nilable(User)).returns Promise[Billing::Money] }
  def async_total_monthly_pledged_in_dollars_visible_to(viewer)
    async_sponsors_listing.then do |sponsors_listing|
      next Billing::Money.zero unless sponsors_listing
      sponsors_listing.async_adminable_by?(viewer).then do |is_adminable|
        next Billing::Money.zero unless is_adminable
        async_active_recurring_sponsorships_as_sponsorable.then do |active_recurring_sponsorships|
          Sponsorship.async_total_recurring_monthly_price_in_cents(active_recurring_sponsorships,
            viewer: viewer
          ).then do |total_monthly_pledged_in_cents|
            Billing::Money.new(total_monthly_pledged_in_cents)
          end
        end
      end
    end
  end

  # Public: Get the estimated next GitHub Sponsors payout visible to the viewer.
  #
  # viewer - currently authenticated User or nil
  #
  # Returns a Billing::Money. $0 can also indicate the viewer is not allowed to see the actual amount.
  sig { params(viewer: T.nilable(User)).returns Promise[Billing::Money] }
  def async_estimated_next_sponsors_payout_in_cents_visible_to(viewer)
    async_sponsors_listing.then do |sponsors_listing|
      next Billing::Money.zero unless sponsors_listing
      sponsors_listing.async_active_stripe_account_balance_visible_to(viewer).then do |balance|
        balance.exchange_to(Billing::Money.default_currency)
      end
    end
  end

  # Public: Get a count of how many users and organizations are sponsoring this user/org.
  sig { returns Integer }
  def total_sponsors
    active_sponsorships_as_sponsorable.count
  end

  # Public: Can private sponsorships from this user/org be seen by the viewer such that the viewer knows this user/org
  # is the sponsor?
  sig { params(viewer: T.nilable(User)).returns T.nilable(T::Boolean) }
  def private_sponsor_identity_visible_to?(viewer)
    return true if sponsorship_amounts_as_sponsor_readable_by?(viewer)
    if organization? && viewer
      T.cast(self, Organization).member?(viewer) || sponsoring_parent_organization&.member?(viewer)
    else
      false
    end
  end

  # Public: Check if the specified user has permission to see how much money this user or organization spends on
  # sponsorships. Keep in sync with #async_sponsorship_amounts_as_sponsor_readable_by?.
  sig { params(viewer: T.nilable(User)).returns T.nilable(T::Boolean) }
  def sponsorship_amounts_as_sponsor_readable_by?(viewer)
    return false unless viewer
    return false unless GitHub.sponsors_enabled?

    @sponsorship_amounts_as_sponsor_readable_by_viewer_id ||= {}
    if @sponsorship_amounts_as_sponsor_readable_by_viewer_id.key?(viewer.id)
      return @sponsorship_amounts_as_sponsor_readable_by_viewer_id[viewer.id]
    end

    @sponsorship_amounts_as_sponsor_readable_by_viewer_id[viewer.id] = if organization?
      T.cast(self, Organization).billing_manageable_by?(viewer) ||
        sponsoring_parent_organization&.billing_manageable_by?(viewer)
    else
      viewer == self
    end
  end

  # Public: The total amount of money that this user or organization has paid into GitHub Sponsors in the form of
  # sponsorships, if the given viewer is allowed to know. Includes funding made by the organization linked to this one
  # for sponsorships, if any.
  #
  # viewer - the currently authenticated User
  # since_time - optional way to limit which payments are summed; if given, only payments that occurred on or
  #              after this time will be included
  # until_time - optional way to limit which payments are summed; if given, only payments that occurred
  #              before this time will be included
  # sponsorable_ids - optional Array of Integer User and Organization IDs for filtering; if any are given, only
  #                   payments made to these maintainers will be included
  #
  # Returns a Promise<Billing::Money|nil> where nil implies the viewer doesn't have permission.
  sig do
    params(
      viewer: T.nilable(User),
      since_time: T.nilable(T.any(Time, DateTime)),
      until_time: T.nilable(T.any(Time, DateTime)),
      sponsorable_ids: T.nilable(T::Array[Integer])
    ).returns(Promise[T.nilable(Billing::Money)])
  end
  def async_total_funded_via_github_sponsors(viewer:, since_time: nil, until_time: nil, sponsorable_ids: [])
    async_sponsorship_amounts_as_sponsor_readable_by?(viewer).then do |is_allowed|
      next unless is_allowed
      promise = if organization?
        Promise.all([T.cast(self, Organization).async_organization_profile, async_sponsors_plan_subscription])
      else
        Promise.resolve(nil)
      end
      promise.then do
        total_funded_via_github_sponsors(since_time: since_time, until_time: until_time,
          sponsorable_ids: sponsorable_ids)
      end
    end
  end

  # Public: The total amount of money that this user or organization has paid into GitHub Sponsors in the form of
  # sponsorships. Includes funding made by the organization linked to this one for sponsorships, if any. Excludes
  # service fees paid to GitHub because that money doesn't go to the maintainers.
  #
  # since_time - optional way to limit which payments are summed; if given, only payments that occurred on or
  #              after this time will be included
  # until_time - optional way to limit which payments are summed; if given, only payments that occurred
  #              before this time will be included
  # sponsorable_ids - optional Array of Integer User and Organization IDs for filtering; if any are given, only
  #                   payments made to these maintainers will be included
  sig do
    params(
      since_time: T.nilable(T.any(Time, DateTime)),
      until_time: T.nilable(T.any(Time, DateTime)),
      sponsorable_ids: T.nilable(T::Array[Integer])
    ).returns(Billing::Money)
  end
  def total_funded_via_github_sponsors(since_time: nil, until_time: nil, sponsorable_ids: [])
    total_cents = 0
    sponsor_ids = [id] # what all sponsors should we consider sponsorships from?

    # Any org might have paid for sponsorships via invoice in the past, so check to see if any invoice records exist:
    if organization?
      sponsor_ids << T.cast(self, Organization).sponsoring_linked_organization_id
      sponsor_ids = sponsor_ids.compact # in case there wasn't a linked org

      if since_time && until_time
        time_range = since_time...until_time
      elsif since_time
        time_range = since_time..
      elsif until_time
        time_range = ...until_time
      end
      invoiced_line_items = Sponsors::InvoicedSponsorshipLineItem.for_org(self, time_range: time_range,
        sponsorable_ids: sponsorable_ids)
      total_cents += invoiced_line_items.sum(&:amount_in_cents)
    end

    line_items = Billing::BillingTransaction::LineItem.sponsorships.for_user(sponsor_ids).paid
    if since_time
      line_items = line_items.transaction_created_at_or_after(since_time)
    end
    if until_time
      line_items = line_items.transaction_created_before(until_time)
    end
    if sponsorable_ids.present?
      line_items = line_items.paying_sponsorable(sponsorable_ids)
    end

    total_cents += line_items.to_a.reject(&:sponsors_fee?).sum(&:amount_in_cents)

    Billing::Money.new(total_cents)
  end

  # Public: Check if the specified user has permission to see how much money this user or organization spends on
  # sponsorships. Keep in sync with #sponsorship_amounts_as_sponsor_readable_by?.
  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsorship_amounts_as_sponsor_readable_by?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer && GitHub.sponsors_enabled?

    @sponsorship_amounts_as_sponsor_readable_by_viewer_id ||= {}
    if @sponsorship_amounts_as_sponsor_readable_by_viewer_id.key?(viewer.id)
      return Promise.resolve(@sponsorship_amounts_as_sponsor_readable_by_viewer_id[viewer.id])
    end

    if organization?
      # Org admins and billing managers can know how much $ their org is paying:
      T.cast(self, Organization).async_billing_manageable_by?(viewer).then do |can_viewer_manage_billing|
        if can_viewer_manage_billing
          @sponsorship_amounts_as_sponsor_readable_by_viewer_id[viewer.id] = true
          next true
        end

        async_sponsoring_parent_organization.then do |parent_org|
          unless parent_org
            @sponsorship_amounts_as_sponsor_readable_by_viewer_id[viewer.id] = false
            next false
          end

          parent_org.async_billing_manageable_by?(viewer).then do |can_viewer_manage_billing|
            @sponsorship_amounts_as_sponsor_readable_by_viewer_id[viewer.id] = can_viewer_manage_billing
          end
        end
      end
    else
      is_viewer = viewer == self
      @sponsorship_amounts_as_sponsor_readable_by_viewer_id[viewer.id] = is_viewer
      Promise.resolve(is_viewer)
    end
  end

  # Public: Get the earliest date this user or organization started sponsoring anyone. Also considers the earliest
  # sponsorship made by this organization's linked organization for sponsorships, if one exists.
  sig { returns T.nilable(T.any(DateTime, ActiveSupport::TimeWithZone)) }
  def earliest_sponsorship_date_as_sponsor
    times = []
    sponsor_ids = [id] # what all sponsors should we consider sponsorships from?

    if organization?
      sponsor_ids << T.cast(self, Organization).sponsoring_linked_organization_id
      sponsor_ids = sponsor_ids.compact # in case there wasn't a linked org

      # Any org might have paid for sponsorships via invoice in the past, so check to see if one exists:
      invoiced_line_item = Sponsors::InvoicedSponsorshipLineItem.first_for_org(self)
      times << invoiced_line_item.created_at if invoiced_line_item
    end

    sponsorship = Sponsorship.from_sponsor(sponsor_ids).paid.order(:created_at).select(:created_at).first
    times << sponsorship.created_at if sponsorship

    times.min
  end

  # Public: Check if the specified user has permission to see how much money this user or organization is receiving
  # in sponsorships.
  #
  # viewer - a User or nil
  #
  # Returns a Boolean.
  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def sponsorship_amounts_as_sponsorable_readable_by?(viewer)
    adminable_by?(viewer)
  end

  # Public: Check if the specified user has permission to see how much money this user or organization is receiving
  # in sponsorships.
  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsorship_amounts_as_sponsorable_readable_by?(viewer)
    async_adminable_by?(viewer)
  end

  # Public: Get a list of users and organizations who are sponsoring this user/org that the specified viewer is
  # allowed to see are sponsors.
  #
  # viewer - User who's currently authenticated; used to ensure private sponsorships are excluded as
  #          necessary, and to sort the returned sponsors so those most relevant to the viewer are first
  # sponsorships_scope - optional Sponsorship scope to filter which sponsors are included
  # order - optional GitHubSponsors::Types::SponsorOrder to sort the returned list of sponsors; relevance only works
  #         if viewer is non-nil
  # direction - optional Symbol to choose the sort order for the returned list; choose from :asc or :desc
  #
  # Returns an ActiveRecord::Relation of User.
  sig do
    params(
      viewer: T.nilable(User),
      sponsorships_scope: T.nilable(ActiveRecord::Relation),
      order: GitHubSponsors::Types::SponsorOrder,
      direction: Symbol
    ).returns(ActiveRecord::Relation)
  end
  def sponsors_visible_to(viewer, sponsorships_scope: nil, order: GitHubSponsors::Types::SponsorOrder::Relevance, direction: :desc)
    sponsorships_scope ||= Sponsorship
    sponsorships_scope = T.unsafe(sponsorships_scope).sponsor_visible_to(viewer)
    users = all_active_sponsors(sponsorships_scope: sponsorships_scope)

    if viewer && order == GitHubSponsors::Types::SponsorOrder::Relevance
      users = T.unsafe(User).ranked_for(viewer, scope: users, direction: direction)
    elsif order == GitHubSponsors::Types::SponsorOrder::Login
      users = users.order(login: direction)
    end

    users.filter_spam_for(viewer)
  end

  # Public: Get a list of users and organizations who are sponsoring this user/org, whether privately or publicly
  # sponsoring.
  #
  # sponsorships_scope - optional Sponsorship scope to filter which sponsors are included
  #
  # Returns an ActiveRecord::Relation of User.
  sig { params(sponsorships_scope: T.nilable(ActiveRecord::Relation)).returns(ActiveRecord::Relation) }
  def all_active_sponsors(sponsorships_scope: nil)
    sponsorships = active_sponsorships_as_sponsorable
    sponsorships = sponsorships.merge(sponsorships_scope) if sponsorships_scope
    sponsor_ids = Sponsorship.sponsor_ids_from(sponsorships)
    User.where(id: sponsor_ids)
  end

  # Public: Get a list of users and organizations who this user/org is sponsoring, whether privately or publicly.
  #
  # sponsorships_scope - optional Sponsorship scope to filter which sponsored users/orgs are included
  #
  # Returns an ActiveRecord::Relation of User.
  def all_active_sponsoring(sponsorships_scope: nil)
    sponsorships = active_sponsorships_as_sponsor_relation
    sponsorships = sponsorships.merge(sponsorships_scope) if sponsorships_scope
    sponsorable_ids = sponsorships.pluck(:sponsorable_id)
    User.where(id: sponsorable_ids)
  end

  # Public: Get a list of users and organizations who are sponsoring this user/org that the specified viewer is
  # allowed to see are sponsors.
  #
  # viewer - User who's currently authenticated; used to ensure private sponsorships are excluded as
  #          necessary, and to sort the returned sponsors so those most relevant to the viewer are first
  # tiers - optional Array of SponsorTiers or their IDs to only count sponsors using those tiers
  # order - optional GitHubSponsors::Types::SponsorOrder to sort the returned list of sponsors; relevance only works
  #         if viewer is non-nil
  # direction - optional Symbol to choose the sort order for the returned list; choose from :asc or :desc
  #
  # Returns a Promise resolving to an ActiveRecord::Relation of User.
  sig do
    params(
      viewer: T.nilable(User),
      tiers: T.nilable(T.any(SponsorsTier, T::Array[SponsorsTier], T::Array[Integer])),
      order: GitHubSponsors::Types::SponsorOrder,
      direction: Symbol
    ).returns(Promise[ActiveRecord::Relation])
  end
  def async_sponsors_visible_to(viewer, tiers: nil, order: GitHubSponsors::Types::SponsorOrder::Relevance, direction: :desc)
    sponsorships_scope = Sponsorship.all

    # Filtering by tier comes with additional restrictions because it exposes what price point someone is sponsoring
    # at, which is restricted information.
    if tiers
      if viewer
        sponsorships_scope = sponsorships_scope.with_tier(tiers)

        is_viewer_listing_admin = if organization?
          T.cast(self, Organization).direct_admin_ids.include?(viewer.id)
        else
          viewer.id == id
        end

        # If the viewer isn't the sponsorable, then they should only see their own sponsorships when
        # filtering by tier:
        unless is_viewer_listing_admin
          sponsors_viewer_can_see_tier_for = [viewer.id] + viewer.owned_or_billing_manager_organization_ids
          sponsorships_scope = sponsorships_scope.from_sponsor(sponsors_viewer_can_see_tier_for)
        end
      else
        # Anonymous viewers cannot filter sponsors by what tier they're on:
        sponsorships_scope = Sponsorship.none
      end
    end

    promises = []
    promises << async_active_sponsorships_as_sponsorable
    if viewer && order == GitHubSponsors::Types::SponsorOrder::Relevance
      promises << viewer.async_followings
      promises << viewer.async_following
    end

    Promise.all(promises).then do
      sponsors_visible_to(viewer, sponsorships_scope: sponsorships_scope, order: order, direction: direction)
    end
  end

  # Public: List of users and organizations this user/org is sponsoring.
  #
  # viewer - User who's currently authenticated; used to ensure private sponsorships are excluded as
  #          necessary, and to sort the returned sponsored users/orgs so those most relevant to the viewer are first
  # order - optional GitHubSponsors::Types::SponsorableOrder to sort the returned list of sponsorables; relevance only
  #         works if viewer is non-nil
  # direction - optional Symbol to choose the sort order for the returned list; choose from :asc or :desc
  #
  # Returns an ActiveRecord::Relation of User.
  sig do
    params(
      viewer: T.nilable(User),
      order: GitHubSponsors::Types::SponsorableOrder,
      direction: Symbol
    ).returns(ActiveRecord::Relation)
  end
  def sponsoring_visible_to(viewer, order: GitHubSponsors::Types::SponsorableOrder::Relevance, direction: :desc)
    sponsorships_scope = Sponsorship.sponsor_visible_to(viewer)
    users = all_active_sponsoring(sponsorships_scope: sponsorships_scope)

    if viewer && order == GitHubSponsors::Types::SponsorableOrder::Relevance
      users = T.unsafe(User).ranked_for(viewer, scope: users, direction: direction)
    elsif order == GitHubSponsors::Types::SponsorableOrder::Login
      users = users.order(login: direction)
    end

    users
  end

  # Public: List of users and organizations this user/org is sponsoring.
  #
  # viewer - User who's currently authenticated; used to ensure private sponsorships are excluded as necessary
  # order - optional GitHubSponsors::Types::SponsorableOrder to sort the returned list of sponsorables; relevance only
  #         works if viewer is non-nil
  #
  # Returns Promise resolving to an ActiveRecord::Relation of User.
  sig do
    params(
      viewer: T.nilable(User),
      order: GitHubSponsors::Types::SponsorableOrder,
      direction: Symbol
    ).returns(Promise[ActiveRecord::Relation])
  end
  def async_sponsoring_visible_to(viewer, order: GitHubSponsors::Types::SponsorableOrder::Relevance, direction: :desc)
    promises = []
    promises << T.cast(self, Organization).async_sponsoring_linked_organization if organization?
    promises << viewer.async_following if viewer && order == GitHubSponsors::Types::SponsorableOrder::Relevance
    Promise.all(promises).then do
      sponsoring_visible_to(viewer, order: order, direction: direction)
    end
  end

  # Public: Whether this user has sponsored someone before.
  #
  # new_sponsorship - An optional `Sponsorship` object to ignore when looking for
  #                   previous sponsorships. This is used when we want to know
  #                   whether it's this user's first time being a sponsor right
  #                   after they created their first sponsorship.
  sig { params(new_sponsorship: T.nilable(Sponsorship)).returns T::Boolean }
  def first_time_sponsor?(new_sponsorship: nil)
    other_sponsorships = sponsorships_as_sponsor

    if organization? && T.cast(self, Organization).sponsoring_linked_organization
      other_sponsorships = other_sponsorships
        .or(T.must(T.cast(self, Organization).sponsoring_linked_organization).sponsorships_as_sponsor)
    end

    if new_sponsorship&.persisted?
      other_sponsorships = other_sponsorships
        .where.not(id: new_sponsorship.id)
    end

    !other_sponsorships.exists?
  end

  # Public: Whether this user has been sponsored before.
  #
  # new_sponsorship - An optional `Sponsorship` object to ignore when looking for
  #                   previous sponsorships. This is used when we want to know
  #                   whether it's this user's first time being sponsored right
  #                   after a sponsorship is created.
  sig { params(new_sponsorship: T.nilable(Sponsorship)).returns T::Boolean }
  def first_time_sponsorable?(new_sponsorship: nil)
    other_sponsorships = sponsorships_as_sponsorable

    if new_sponsorship&.persisted?
      other_sponsorships = other_sponsorships
        .where.not(id: new_sponsorship.id)
    end

    !other_sponsorships.exists?
  end

  # Public: Is this user ineligible to have their sponsorships (as sponsor)
  #         matched due to being spammy or not being old enough?
  sig { returns T::Boolean }
  def sponsorship_match_ineligible_from_age_or_spamminess?
    return true if spammy?
    (created_at || Time.now) > 1.month.ago
  end

  # Public: Are the sponsorships created by this user (as sponsor) eligible to
  #         be matched by GitHub?
  #
  # sponsorable - the User or Organization this user/org is trying to sponsor
  sig { params(sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable)).returns T::Boolean }
  def eligible_for_sponsorship_match?(sponsorable:)
    return false unless sponsorable
    return false if sponsorship_match_ineligible_from_age_or_spamminess?
    return false if SponsorshipMatchBan.where(sponsor: self, sponsorable: sponsorable).exists?

    approved_sponsors_listing.blank?
  end

  def sponsors_payouts_enabled?
    sponsors_listing&.payouts_enabled?
  end

  # Public: Get an email address for sending SponsorshipNewsletter messages to the user.
  def sponsors_update_email
    email
  end

  # Public: Get a list of all the users and organizations that this user/org can manage the Sponsors profile for.
  # Preloads the SponsorsListing for each.
  #
  # Returns an Array of User and Organization objects.
  def sponsors_enabled_accounts
    @sponsors_enabled_accounts ||= begin
      User.where(id: potential_sponsorable_ids)
          .by_login
          .includes(:sponsors_listing)
          .to_a
    end
  end

  sig { returns T::Boolean }
  def any_not_banned_sponsors_listing_accounts?
    if defined?(@any_not_banned_sponsors_listing_accounts)
      return @any_not_banned_sponsors_listing_accounts
    end

    not_banned_sponsors_listing_accounts = SponsorsListing.where(
      sponsorable_id: [id] + owned_organization_ids,
    ).without_banned_state

    not_banned_sponsors_listing_accounts = not_banned_sponsors_listing_accounts.without_sdn_disabled_state
    @any_not_banned_sponsors_listing_accounts = not_banned_sponsors_listing_accounts.exists?
  end

  sig { returns T::Boolean }
  def has_ever_sponsored?
    sponsorships_as_sponsor.any?
  end

  sig { returns T::Array[GitHubSponsors::Types::Sponsorable] }
  def sponsors_listing_accounts
    @sponsors_listing_accounts ||=
      sponsors_enabled_accounts.select(&:sponsors_listing)
  end

  sig { returns T::Array[String] }
  def potential_sponsor_logins
    @potential_sponsor_logins ||= potential_sponsor_accounts.pluck(:login)
  end

  sig { returns ActiveRecord::Relation }
  def potential_sponsor_accounts
    User.where(id: potential_sponsor_ids).
      # Order this user first, then other accounts alphabetically by login
      order(Arel.sql("CASE id WHEN #{id} THEN 0 ELSE 1 END")).
      order(:login)
  end

  sig { returns T::Boolean }
  def needs_personal_profile?
    return false unless user?

    !has_saved_trade_screening_record?
  end

  # Public: Is this user one who pays for their sponsorships via a Zuora credit balance from an invoice?
  sig { returns T::Boolean }
  def sponsors_invoiced?
    return @sponsors_invoiced if defined?(@sponsors_invoiced)
    @sponsors_invoiced = T.must(GitHub.sponsors_enabled? && GitHub.billing_enabled? &&
      organization? && sponsors_customer.present? && T.must(sponsors_customer).zuora?)
  end

  # Public: Is this user eligible to switch to paying for their sponsorships via a Zuora credit balance from an invoice?
  sig { returns T::Boolean }
  def can_switch_to_sponsors_invoicing?
    return @can_switch_to_sponsors_invoicing if defined?(@can_switch_to_sponsors_invoicing)
    @can_switch_to_sponsors_invoicing = T.must(organization? && !sponsors_invoiced?)
  end

  sig { returns Integer }
  def public_sponsors_count
    active_sponsorships_as_sponsorable.privacy_public.size
  end

  # Public: Get a count of how many users and organizations this user or organization is sponsoring. That is,
  # how many sponsorships is this user/org funding.
  #
  # include_private - whether to include private sponsorships in the count
  sig { params(include_private: T.nilable(T::Boolean)).returns Integer }
  def sponsoring_count(include_private:)
    return 0 unless GitHub.sponsors_enabled?

    return 0 unless actively_sponsoring?

    if include_private
      public_and_private_sponsoring_count
    else
      public_sponsoring_count
    end
  end

  # Public: Get a count of how many users and organizations this user or organization has sponsored in the past
  # and is not actively sponsoring. That is, how many sponsorships has this user/org funded in the past.
  #
  # include_private - Boolean indicating whether to include private sponsorships in the count
  sig { params(include_private: T::Boolean).returns Integer }
  def inactive_sponsoring_count(include_private:)
    return 0 unless GitHub.sponsors_enabled?

    if include_private
      inactive_public_and_private_sponsoring_count
    else
      inactive_public_sponsoring_count
    end
  end

  sig { returns Integer }
  def public_and_private_sponsors_count
    active_sponsorships_as_sponsorable.size
  end

  sig { returns Integer }
  def public_and_private_sponsoring_count
    active_sponsorships_as_sponsor_relation.size
  end

  sig { returns Integer }
  def public_sponsoring_count
    T.unsafe(active_sponsorships_as_sponsor_relation).privacy_public.size
  end

  sig { returns Integer }
  def inactive_public_sponsoring_count
    sponsorships_as_sponsor.inactive.paid_or_patreon.privacy_public.size
  end

  sig { returns Integer }
  def inactive_public_sponsors_count
    sponsorships_as_sponsorable.inactive.privacy_public.size
  end

  sig { returns Integer }
  def inactive_public_and_private_sponsors_count
    sponsorships_as_sponsorable.inactive.size
  end

  sig { returns Integer }
  def inactive_public_and_private_sponsoring_count
    sponsorships_as_sponsor.inactive.paid_or_patreon.size
  end

  # Public: The Zuora account id of the sponsors-purpose customer, if one exists
  sig { returns T.nilable(String) }
  def invoiced_sponsor_zuora_account_id
    sponsors_customer&.zuora_account_id
  end

  # Public: Does this user have a sponsors customer with a large enough invoiced credit balance to cover a given
  #         payment amount?
  sig { params(sponsorship_amount: Billing::Money).returns(T::Boolean) }
  def sufficient_invoiced_sponsor_balance?(sponsorship_amount)
    return false unless sponsors_invoiced?
    # We know sponsors_customer is not nil because #sponsors_invoiced? checks for it:
    T.must(sponsors_customer).sufficient_balance?(sponsorship_amount)
  end

  # Public: Get IDs of organizations for whom this user can create and manage sponsorships
  # where that org is the sponsor in the sponsorship.
  sig { returns T::Array[Integer] }
  def potential_organization_sponsor_ids
    owned_or_billing_manager_organization_ids + org_ids_from_business_admin_or_billing_manager
  end

  # Public: Get IDs of organizations that are linked to those this user is admin or billing manager of. That is,
  # get orgs that are allowed to pay for sponsorships that orgs this user billing manages receives credit for.
  sig { returns T::Array[Integer] }
  def potential_linked_organization_sponsor_ids
    OrganizationProfile.for_organization(potential_organization_sponsor_ids).pluck(:sponsoring_linked_organization_id)
  end

  # Public: Get IDs of users and organizations on whose behalf this user can sponsor someone.
  # That is, this user is allowed to manage Sponsorship records where the sponsor_id is one
  # of those returned.
  sig { returns T::Array[Integer] }
  def potential_sponsor_ids
    [id, *potential_organization_sponsor_ids].compact
  end

  # Public: Get IDs of users and organizations on whose behalf this user can sign up for GitHub Sponsors.
  # That is, this user is allowed to manage the SponsorsListing record where the sponsorable_id is one
  # of those returned.
  sig { returns T::Array[Integer] }
  def potential_sponsorable_ids
    [id, *owned_organization_ids].compact # does not include billing managed organization IDs
  end

  # Public: Update the user's Sponsors listing so that its slug and Zuora product match the new user login.
  #
  # new_login - String login for this User or Organization
  #
  # Returns a Boolean indicating success. Also true if no updates were necessary or appropriate.
  sig { params(new_login: String).returns(T::Boolean) }
  def update_sponsors_listing_slug(new_login)
    return true unless GitHub.sponsors_enabled?
    return true unless sponsors_listing
    return true unless T.must(sponsors_listing).safe_to_update_slug?
    T.must(sponsors_listing).update_slug(new_login: new_login)
  end

  # Public: Get counts of how many active sponsorships are at each tier. For
  # custom tiers, only the earliest custom tier at each price point is represented.
  #
  # custom_tier_ids - optional list of custom SponsorsTier IDs to include counts for,
  #                   if already known
  #
  # Returns a Hash of SponsorsTier ID => Integer count of active sponsorships.
  sig { params(custom_tier_ids: T.nilable(T::Array[Integer])).returns(T::Hash[Integer, Integer]) }
  def tier_subscription_counts(custom_tier_ids: nil)
    non_custom_sponsorships = active_sponsorships_as_sponsorable.without_custom_tiers
    counts_by_tier_id = Hash.new(0)
      .merge(non_custom_sponsorships.group(:subscribable_id).count)

    if sponsors_listing
      custom_tier_ids ||= T.must(sponsors_listing).unique_custom_tiers.pluck(:id)
    end
    if custom_tier_ids.any?
      custom_sponsorships = active_sponsorships_as_sponsorable
        .only_custom_tiers
        .includes(:tier)
        .select(:subscribable_id)
      tier_ids_by_price = SponsorsTier.where(id: custom_tier_ids)
        .pluck(:monthly_price_in_cents, :id)
        .to_h
      custom_sponsorships.each do |sponsorship|
        custom_tier = sponsorship.tier
        key = tier_ids_by_price[custom_tier.monthly_price_in_cents] || sponsorship.subscribable_id
        counts_by_tier_id[key] += 1
      end
    end

    counts_by_tier_id
  end

  # Public: Is this user allowed to use a fiscal host for their GitHub Sponsors payouts, as opposed to a bank account
  # via Stripe?
  sig { returns T::Boolean }
  def can_use_fiscal_host_for_sponsors?
    organization? || user?
  end

  # Public: Does this user belong to GitHub Sponsors and use a fiscal host that
  # we support to get their payments?
  sig { returns T::Boolean }
  def uses_sponsors_fiscal_host?
    if sponsors_listing
      T.must(sponsors_listing).uses_fiscal_host?
    else
      false
    end
  end

  # Public: Can this user or organization skip proration and pay the full amount?
  #         We skip proration by backdating the sponsorship effective date in Zuora.
  #         If the user/org doesn't have a plan then we can't set an effective date.
  sig { returns T::Boolean }
  def can_skip_sponsorship_proration?
    # we rely on customer_bill_cycle_day, which is not enough info to calculate the
    # backdate for a yearly plan, so we can't skip proration for yearly plans currently.
    return false if yearly_sponsors_plan?

    # we need the bill cycle day to figure out the contract date to use.
    return false unless customer_bill_cycle_day_for_sponsorships.to_i.positive?

    # validate there's an active Zuora subscription, otherwise we get an error
    # from Zuora if we try to set a contract date.
    sponsors_plan_subscription&.zuora_subscription_number.present?
  end

  # Public: Is this user allowed to schedule sponsorships such that they pay nothing today
  #         and pay when the sponsorship is activated at a later date?
  sig { returns T::Boolean }
  def can_schedule_sponsorships?
    sponsors_invoiced?
  end

  def async_sponsoring_parent_organization
    async_sponsoring_parent_organization_profile.then do |profile|
      next unless profile
      profile.async_organization
    end
  end

  def sponsoring_parent_organization
    parent_org_profile = sponsoring_parent_organization_profile
    parent_org_profile&.organization
  end

  def sponsors_fiscally_hosted_project_profile_url
    return unless sponsors_listing
    T.must(sponsors_listing).fiscally_hosted_project_profile_url
  end

  # Public: Get the VAT ID for the sponsor (for sales tax purposes)
  sig { returns T.nilable(String) }
  def sponsor_sales_tax_vat_id
    customer&.vat_code
  end

  # Public: Get tax identifier for the given timestamp
  #
  # timestamp - used for resolving tax information
  sig do
    params(timestamp: T.any(DateTime, ActiveSupport::TimeWithZone)).returns(T.nilable(SponsorsBusinessTaxIdentifier))
  end
  def sponsors_business_tax_identifier_at(timestamp)
    sponsors_business_tax_identifiers.find do |identifier|
      # HACK HACK HACK line item created_at timestamps don't have subsecond resolution,
      # so we pretend identifiers don't either.
      identifier_created_at = T.must(identifier.created_at).change(usec: 0)
      timestamp >= identifier_created_at
    end
  end

  # Public: Get the plan duration specific to sponsorships
  #
  # Premium sponsors may have a yearly plan for their general-purpose plan subscription,
  # but their sponsorships will still be billed monthly.
  #
  # Returns a String ("year" or "month").
  sig { returns String }
  def sponsors_plan_duration
    if sponsors_invoiced?
      User::BillingDependency::MONTHLY_PLAN
    else
      plan_duration
    end
  end

  # Public: Is this user billed yearly for sponsorships?
  sig { returns T::Boolean }
  def yearly_sponsors_plan?
    sponsors_plan_duration == User::BillingDependency::YEARLY_PLAN
  end

  # Public: Get the next billing date for sponsorships
  #
  # If as Org has a sponsors-purpose plan subscription we know they'll be
  # billed monthly so we use the bill cycle day on the sponsors-purpose
  # customer to calculate their next billing date.
  #
  # Otherwise we fall back to the `next_billing_date` as the default.
  sig { returns Date }
  def next_sponsors_billing_date
    if sponsors_invoiced?
      # A value of zero means a subscription hasn't been created yet and the
      # User/Org will be billed today.
      return GitHub::Billing.today if sponsors_customer_bill_cycle_day == 0

      today_in_billing_month = if GitHub::Billing.today.day < sponsors_customer_bill_cycle_day
        GitHub::Billing.today
      else
        GitHub::Billing.today + 1.month
      end
      # bill cycle days extend to 31, and during a month with fewer days
      # Zuora will bill on the last day of the month.
      begin
        billing_date = today_in_billing_month.change(day: sponsors_customer_bill_cycle_day)
      rescue Date::Error
        billing_date = today_in_billing_month.end_of_month
      end

      billing_date
    else
      T.must_because(next_billing_date(with_dunning: false)) do
        "#next_billing_date can only return nil when with_dunning=true"
      end
    end
  end

  # Public: Returns a String representing the next billing date for sponsorships.
  sig { returns T.nilable(String) }
  def formatted_next_sponsors_billing_date
    if yearly_sponsors_plan?
      next_sponsors_billing_date.strftime("%B %-d, %Y")
    else
      next_sponsors_billing_date.strftime("%B %-d")
    end
  end

  # Public: Return a Sponsors::TrustLevel::Result representing the trust level for a funder.
  sig { returns Sponsors::TrustLevel::Result }
  def trust_level_as_sponsor
    Sponsors::TrustLevel.as_sponsor(self)
  end

  # Public: Return a Sponsors::TrustLevel::Result representing the trust level for a maintainer.
  sig { returns Sponsors::TrustLevel::Result }
  def trust_level_as_sponsorable
    Sponsors::TrustLevel.as_sponsorable(self)
  end

  # Public: Is this User/Org untrusted as a sponsor?
  sig { returns T::Boolean }
  def untrusted_as_sponsor?
    trust_level_as_sponsor.untrusted?
  end

  # Public: Is this User/Org untrusted as a sponsorable?
  sig { returns T::Boolean }
  def untrusted_as_sponsorable?
    trust_level_as_sponsorable.untrusted?
  end

  # Public: Zero balance date for Sponsors-invoiced customer's credit balance
  sig { returns T.nilable(Date) }
  def sponsors_zero_balance_date
    return unless sponsors_invoiced?

    sponsorships = sponsorships_as_sponsor.active.recurring
    # sponsors_customer is non-nil because of #sponsors_invoiced? check above:
    current_balance = T.must(sponsors_customer).credit_balance

    low_balance_calculator = Sponsors::ZeroBalanceDateCalculator.new(
      sponsorships: sponsorships,
      current_balance: current_balance,
      customer: sponsors_customer,
    )
    low_balance_calculator.zero_balance_date
  end

  sig { returns T.nilable(CustomerAccount) }
  def sponsors_customer_account
    return super if association(:sponsors_customer_account).loaded?
    customer_accounts.detect(&:sponsors_purpose?)
  end

  # Public: Boolean if this user has an external sponsors-purpose subscription linked
  sig { returns T::Boolean }
  def external_sponsors_subscription?
    T.must(sponsors_plan_subscription.present? && T.must(sponsors_plan_subscription).has_external_subscription?)
  end

  sig { returns T.nilable(Customer) }
  def sponsors_customer
    return super if association(:sponsors_customer).loaded?
    return sponsors_customer_account&.customer if association(:sponsors_customer_account).loaded?
    customers.detect(&:sponsors_purpose?)
  end

  sig { returns Integer }
  def sponsors_customer_bill_cycle_day
    return 0 unless sponsors_customer
    T.must(sponsors_customer).bill_cycle_day.to_i
  end

  # Public: If this user has a Zuora account for Sponsors billing.
  sig { returns T.nilable(T::Boolean) }
  def sponsors_zuora_account?
    sponsors_customer&.zuora?
  end

  # Public: Whether this user should be charged fees for sponsorships at time of sponsorship payment.
  sig { returns T.nilable(T::Boolean) }
  def should_pay_fees_at_sponsorship_payment_time?
    organization? && # only orgs pay fees
      !sponsors_zuora_account? # invoiced orgs pay fees at invoice time, not sponsorship payment time
  end

  # Public: Get the user's preferred payment method for sponsorships.
  sig { returns T.nilable(PaymentMethod) }
  def sponsors_payment_method
    return T.must(sponsors_customer).payment_method if association(:sponsors_customer).loaded? && sponsors_customer
    if association(:sponsors_customer_account).loaded? && sponsors_customer_account
      if T.must(sponsors_customer_account).customer
        return T.must(T.must(sponsors_customer_account).customer).payment_method
      end
    end

    customer_list = customers.to_a
    GitHub::PrefillAssociations.prefill_associations(customer_list, :payment_method)

    sponsors_purpose_customer = customers.detect(&:sponsors_purpose?)
    if sponsors_purpose_customer
      sponsors_purpose_customer.payment_method
    else
      payment_method
    end
  end

  # Public: Boolean if a user has a PayPal account that would be used to pay for the account's sponsorships.
  #
  # Returns truthy if there is a external vault Sponsors-specific or general-purpose customer with a PayPal account.
  def has_paypal_account_for_sponsors?
    return false if sponsors_invoiced?
    return T.must(sponsors_payment_method).paypal? if sponsors_payment_method.present?
    has_paypal_account?
  end

  # Public: Check if this user has a valid payment method on file for use with sponsorships. Will check for a
  # sponsorships-specific payment method as well as a general-purpose payment method.
  # feature_type - by default we require valid contact info to be present before performing any commercial interactions. There are some scenarios where it is okay to bypass this check.
  #   For any scenarios where the check is made for non-commercial interactions, use ':noncommercial' feature type (example when allowing a customer to remove a payment method)
  sig { params(feature_type: Symbol).returns(T::Boolean) }
  def has_valid_payment_method_for_sponsorships?(feature_type: :default)
    return false if has_paypal_account_for_sponsors?

    return true if sponsors_invoiced?
    return true if sponsors_payment_method&.valid_payment_token? && has_valid_trade_screening_record_for_payment?(feature_type:)
    return true if organization? && business.present? && business.has_valid_payment_method_for_sponsorships?(feature_type:)

    has_valid_payment_method?(feature_type:)
  end

  # Public: Can another GitHub user/organization sponsor this user/organization via GitHub Sponsors while making
  # their payment via Patreon?
  sig { returns T.nilable(T::Boolean) }
  def sponsorable_via_patreon?
    return false unless sponsorable?

    spu = sponsors_patreon_user
    spu&.enabled_as_sponsorable? && spu.any_valid_patreon_tiers?
  end

  # Public: Returns the day of the month the user is billed for sponsorships, regardless of whether they're using
  #         a Sponsors-specific or general-purpose account to pay for sponsorships.
  sig { returns T.nilable(Integer) }
  def customer_bill_cycle_day_for_sponsorships
    sponsorships_customer = customer_for(:sponsors) || customer_for(:general)
    sponsorships_customer&.bill_cycle_day.to_i
  end

  # Public: Get SponsorsTier IDs that have been added to a bulk sponsorship event and that have yet to be paid for
  sig { returns T::Set[Integer] }
  def payment_incomplete_bulk_sponsorship_tier_ids
    return Set.new unless persisted?

    tier_selection = bulk_sponsorship_tier_selection
    return tier_selection.sponsors_tier_ids.to_set if tier_selection

    Set.new
  end

  # Public: Preserve a list of sponsorship tiers that this user chose in a bulk sponsorship,
  # so that we can verify later, as payments process, that the individual sponsorships
  # were made as part of a bulk sponsorship.
  #
  # tier_ids - a Set or Array of SponsorsTier IDs
  sig { params(tier_ids: T.any(T::Array[Integer], T::Set[Integer])).returns(T::Boolean) }
  def save_bulk_sponsorship_tier_ids(tier_ids)
    return false unless tier_ids.present? && persisted?

    tier_selection = bulk_sponsorship_tier_selection || build_bulk_sponsorship_tier_selection
    tier_selection.sponsors_tier_ids = tier_ids.to_a
    tier_selection.save
  end

  # Public: Clear the user's list of payment-incomplete bulk sponsorship tiers.
  sig { void }
  def clear_bulk_sponsorship_tier_ids
    return unless persisted?

    tier_selection = bulk_sponsorship_tier_selection
    tier_selection&.destroy
  end

  # Public: Get a list of hashes of maintainer logins and amounts to sponsor them for from CSV imported by the User
  sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }] }
  def amounts_by_sponsorable_login_bulk_sponsorship_import
    return [] unless persisted?

    import = bulk_sponsorship_import
    return import.data if import && !import.expired?

    []
  end

  # Public: Temporarily preserve a bulk sponsorship import containing a list of User logins and amounts to sponsor
  # them for. We do this so that the user can go back and forth between reviewing and checking out their bulk
  # sponsorship import. It is temporary because its purpose is contained to the lifespan of a checkout process.
  sig { params(data: T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }]).returns(T::Boolean) }
  def save_bulk_sponsorship_import(data)
    return false unless data.present?
    return false unless persisted?

    import = bulk_sponsorship_import || build_bulk_sponsorship_import
    import.data = data
    import.save
  end

  sig { returns T::Boolean }
  def active_invoiced_sponsors_agreement?
    # users cannot have invoiced sponsors agreements, only orgs
    false
  end

  sig { returns(T.nilable(String)) }
  def sponsors_patreon_link
    sponsors_patreon_user&.patreon_link
  end

  sig { returns(T.nilable(String)) }
  def sponsors_patreon_membership_link
    sponsors_patreon_user&.patreon_membership_link
  end

  sig { returns(T.nilable(String)) }
  def sponsors_patreon_username
    sponsors_patreon_user&.patreon_username
  end

  # Public: Indicates if we show the option to pay the prorated amount when a
  #         user goes create a sponsorship as the default option.
  sig { returns(T::Boolean) }
  def sponsors_prorated_by_default?
    true
  end

  sig { returns(T::Boolean) }
  def sponsors_invoicing_required_to_sponsor?
    false
  end

  private

  sig { void }
  def alert_sponsors_listing_time_zone_changed
    return unless previous_changes[:time_zone_name]
    sponsors_listing_stafftools_metadata&.update_column(:sponsorable_time_zone_name, self.time_zone_name)
  end

  sig { params(tier_ids: T.any(T::Array[Integer], T::Set[Integer])).void }
  def remove_tiers_from_bulk_sponsorship_event(tier_ids)
    stored_tier_ids = payment_incomplete_bulk_sponsorship_tier_ids
    remaining_tier_ids = stored_tier_ids - tier_ids

    if remaining_tier_ids.empty?
      clear_bulk_sponsorship_tier_ids
    else
      save_bulk_sponsorship_tier_ids(remaining_tier_ids)
    end
  end

  sig { params(sponsors_tiers: T::Array[SponsorsTier]).returns(ActiveRecord::Relation) }
  def sponsorships_for_instrument_payment_complete(sponsors_tiers)
    tier = sponsors_tiers.first
    return Sponsorship.none unless tier

    base_query = Sponsorship.active.from_sponsor(self)
    sponsorships = base_query.for_listing(tier.sponsors_listing_id)
    sponsors_tiers.drop(1).each do |tier|
      sponsorships = sponsorships.or(base_query.for_listing(tier.sponsors_listing_id))
    end

    # Relations used by Sponsorship#instrument_payment_complete:
    sponsorships.includes(:sponsor, :sponsors_listing,
      :sponsorable, # used by Sponsorship#matchable?
      :invoiced_sponsorship_transfer, # used by Sponsorship#manual_invoiced?
      :subscription_item, # used by Sponsorship#sponsors_invoiced?
      :tier, # used by Sponsorship#recurring_payment?
    )
  end

  sig { params(tiers_paid: T::Array[SponsorsTier]).void }
  def send_now_sponsoring_via_bulk_sponsorship_email(tiers_paid)
    return unless tiers_paid.any?

    SendNowSponsoringViaBulkSponsorshipEmailJob.perform_later(
      sponsor: T.cast(self, User),
      tiers_paid: tiers_paid,
    )
  end

  sig { returns T::Array[Integer] }
  def admin_or_billing_manager_business_ids
    business_admin_ability_ids + business_billing_management_ability_ids
  end

  # The organizations this user can sponsor as via their business admin or business billing manager abilities
  sig { returns T::Array[Integer] }
  def org_ids_from_business_admin_or_billing_manager
    Business::OrganizationMembership.where(business_id: admin_or_billing_manager_business_ids).pluck(:organization_id)
  end
end
