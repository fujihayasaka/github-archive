# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Sponsorable
      include Interfaces::Base

      description "Entities that can sponsor or be sponsored through GitHub Sponsors."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      field :sponsors_listing, Objects::SponsorsListing,
        description: "The GitHub Sponsors listing for this user or organization.", null: true

      sig { returns Promise[T.nilable(SponsorsListing)] }
      def sponsors_listing
        @object.async_sponsors_listing.then do |listing|
          next unless listing.present?

          listing.async_readable_by?(@context[:viewer]).then do |readable_by|
            next unless readable_by
            listing
          end
        end
      end

      field :has_sponsors_listing, Boolean,
        description: "True if this user/organization has a GitHub Sponsors listing.", null: false,
        method: :async_sponsorable?

      field(:total_sponsorship_amount_as_sponsor_in_cents, Integer,
        description: "The amount in United States cents (e.g., 500 = $5.00 USD) that this entity has spent on " \
          "GitHub to fund sponsorships. Only returns a value when viewed by the user themselves or by a user who " \
          "can manage sponsorships for the requested organization.",
        null: true,
      ) do
        argument :since, Scalars::DateTime,
          "Filter payments to those that occurred on or after this time.", required: false
        argument :until, Scalars::DateTime,
          "Filter payments to those that occurred before this time.", required: false
        argument :sponsorable_logins, [String], "Filter payments to those made to the users or organizations with " \
          "the specified usernames.", required: false, default_value: []
      end

      sig do
        params(
          since: T.nilable(T.any(DateTime, Time)),
          sponsorable_logins: T::Array[String],
          arguments: T.untyped,
        ).returns(Promise[Integer])
      end
      def total_sponsorship_amount_as_sponsor_in_cents(since: nil, sponsorable_logins: [], **arguments)
        sponsorable_promises = sponsorable_logins.map do |login|
          Loaders::ActiveRecord.load(::User, login, column: :login)
        end
        Promise.all(sponsorable_promises).then do |sponsorables|
          # `until` is a reserved word in Ruby so can't have `until` as a named parameter, have to get it from
          # `arguments` hash:
          until_time = arguments[:until]

          @object.async_total_funded_via_github_sponsors(
            viewer: @context[:viewer],
            since_time: since,
            until_time: until_time,
            sponsorable_ids: sponsorables.compact.map(&:id),
          ).then { |money| money&.cents }
        end
      end

      DEFAULT_LIFETIME_RECEIVED_SPONSORSHIP_VALUES_ORDER = {
        field: GitHubSponsors::Types::SponsorAndLifetimeValueOrder::SponsorLogin.serialize,
        direction: "ASC",
      }

      field(:lifetime_received_sponsorship_values, Connections.define(Objects::SponsorAndLifetimeValue),
        null: false,
        connection: true,
        visibility: {
          internal: { environments: [:enterprise] },
          public: { environments: [:dotcom] },
        },
        description: "Calculate how much each sponsor has ever paid total to this maintainer via GitHub Sponsors. " \
          "Does not include sponsorships paid via Patreon.",
      ) do
        argument :order_by, Inputs::SponsorAndLifetimeValueOrder,
          "Ordering options for results returned from the connection.", required: false,
          default_value: DEFAULT_LIFETIME_RECEIVED_SPONSORSHIP_VALUES_ORDER
      end

      sig do
        params(
          order_by: T.any(Inputs::SponsorAndLifetimeValueOrder, { field: String, direction: String })
        ).returns(Promise[T::Array[Platform::Models::SponsorAndLifetimeValue]])
      end
      def lifetime_received_sponsorship_values(order_by: DEFAULT_LIFETIME_RECEIVED_SPONSORSHIP_VALUES_ORDER)
        viewer = @context[:viewer]
        field = GitHubSponsors::Types::SponsorAndLifetimeValueOrder.from_serialized(order_by[:field])
        direction = order_by[:direction].downcase.to_sym

        Loaders::LifetimeSponsorshipValues.load(@object.id, viewer: viewer).then do |amounts_by_sponsor_id|
          amounts_by_sponsor_id ||= {}
          sponsor_ids = amounts_by_sponsor_id.keys.sort # keep a stable order of results for pagination
          unsorted_results = sponsor_ids.map do |sponsor_id|
            amount = amounts_by_sponsor_id[sponsor_id] || Billing::Money.zero
            Platform::Models::SponsorAndLifetimeValue.new(sponsor_id: sponsor_id, amount: amount,
              sponsorable: @object)
          end
          Platform::Models::SponsorAndLifetimeValue.async_sort(unsorted_results,
            field: field,
            direction: direction,
            viewer: viewer,
          ).then do |sorted_results|
            ArrayWrapper.new(sorted_results)
          end
        end
      end

      DEFAULT_SPONSORS_ORDER = { field: "relevance", direction: "DESC" }

      field(:sponsors, Connections::Sponsor, description: "List of sponsors for this user or organization.",
        null: false, connection: true,
      ) do
        argument :tier_id, ID, "If given, will filter for sponsors at the given tier. Will only return sponsors " \
          "whose tier the viewer is permitted to see.", required: false
        argument :order_by, Inputs::SponsorOrder,
          "Ordering options for sponsors returned from the connection.", required: false,
          default_value: DEFAULT_SPONSORS_ORDER
      end

      sig do
        params(
          tier_id: T.nilable(String),
          order_by: T.any(Inputs::SponsorOrder, { field: String, direction: String })
        ).returns(Promise[T::Array[GitHubSponsors::Types::Sponsor]])
      end
      def sponsors(tier_id: nil, order_by: DEFAULT_SPONSORS_ORDER)
        tier = if tier_id
          Platform::Helpers::NodeIdentification.typed_object_from_id(Objects::SponsorsTier, tier_id, @context)
        end

        order = if order_by[:field] == "login"
          GitHubSponsors::Types::SponsorOrder::Login
        else
          GitHubSponsors::Types::SponsorOrder::Relevance
        end
        direction = order_by[:direction].downcase.to_sym

        @object.async_sponsors_visible_to(@context[:viewer], tiers: tier, order: order, direction: direction)
      end

      DEFAULT_SPONSORING_ORDER = { field: "relevance", direction: "DESC" }

      field(:sponsoring, Connections::Sponsor,
        description: "List of users and organizations this entity is sponsoring.", null: false, connection: true,
      ) do
        argument :order_by, Inputs::SponsorOrder,
          "Ordering options for the users and organizations returned from the connection.", required: false,
          default_value: DEFAULT_SPONSORING_ORDER
      end

      sig do
        params(
          order_by: T.any(Inputs::SponsorOrder, { field: String, direction: String }),
        ).returns(T.any(
          Promise[T::Array[GitHubSponsors::Types::Sponsorable]],
          T::Array[GitHubSponsors::Types::Sponsorable]
        ))
      end
      def sponsoring(order_by: DEFAULT_SPONSORING_ORDER)
        return ArrayWrapper.new([]) if @object.private_profile_for?(@context[:viewer])

        order = if order_by[:field] == "login"
          GitHubSponsors::Types::SponsorableOrder::Login
        else
          GitHubSponsors::Types::SponsorableOrder::Relevance
        end
        direction = order_by[:direction].downcase.to_sym
        @object.async_sponsoring_visible_to(@context[:viewer], order: order, direction: direction)
      end

      field :viewer_is_sponsoring, Boolean, description: "True if the viewer is sponsoring this user/organization.",
        null: false

      sig { returns T.any(T::Boolean, Promise[T::Boolean]) }
      def viewer_is_sponsoring
        return false unless @context[:viewer]

        # sponsored_by_viewer? batches on sponsorable_id
        @object.async_sponsored_by_viewer?(@context[:viewer])
      end

      field :is_sponsored_by, Boolean,
        "Whether the given account is sponsoring this user/organization.",
        visibility: {
          internal: { environments: [:enterprise] },
          public: { environments: [:dotcom] },
        }, null: false do
          argument :account_login, String, "The target account's login.", required: true
        end

      sig { params(account_login: String).returns(Promise[T::Boolean]) }
      def is_sponsored_by(account_login:)
        Loaders::ActiveRecord.load(::User, account_login,
          column: :login,
          case_sensitive: false,
        ).then do |account|
          if account.nil? || account.hide_from_user?(@context[:viewer])
            raise Errors::NotFound, "Could not resolve to a User or Organization with " \
              "the login of '#{account_login}'."
          end

          Platform::Loaders::IsSponsoringCheck.load(
            sponsor_id: account.id,
            sponsorable_id: @object.id,
            viewer: @context[:viewer],
          )
        end
      end

      field :is_sponsoring_viewer, Boolean, description: "True if the viewer is sponsored by this user/organization.",
        null: false

      sig { returns T.any(T::Boolean, Promise[T::Boolean]) }
      def is_sponsoring_viewer
        return false unless @context[:viewer]

        # IsSponsorCheck batches on sponsor_id
        Platform::Loaders::IsSponsorCheck.load(
          sponsorable_id: @context[:viewer].id,
          sponsor_id: @object.id,
          include_private: true
        )
      end

      field :viewer_can_sponsor, Boolean,
        description: "Whether or not the viewer is able to sponsor this user/organization.", null: false

      sig { returns Promise[T::Boolean] }
      def viewer_can_sponsor
        @object.async_sponsorable_by?(@context[:viewer])
      end

      DEFAULT_NEWSLETTER_ORDER = { field: "created_at", direction: "DESC" }

      field(:sponsorship_newsletters, Connections.define(Objects::SponsorshipNewsletter),
        description: "List of sponsorship updates sent from this sponsorable to sponsors.", null: false,
        connection: true,
      ) do
        argument :order_by, Inputs::SponsorshipNewsletterOrder,
          "Ordering options for sponsorship updates returned from the connection.", required: false,
          default_value: DEFAULT_NEWSLETTER_ORDER
      end

      sig do
        params(
          order_by: T.any(Inputs::SponsorshipNewsletterOrder, { field: String, direction: String })
        ).returns(ActiveRecord::Relation)
      end
      def sponsorship_newsletters(order_by: DEFAULT_NEWSLETTER_ORDER)
        field = order_by[:field]
        direction = order_by[:direction]
        @object.sponsorship_newsletters
          .visible_to(@context[:viewer])
          .order("sponsorship_newsletters.#{field} #{direction}")
      end

      field(:sponsorship_for_viewer_as_sponsor, Objects::Sponsorship,
        description: "The sponsorship from the viewer to this user/organization; that is, the sponsorship where " \
          "you're the sponsor.",
        null: true,
      ) do
        argument :active_only, Boolean, "Whether to return the sponsorship only if it's still active. Pass false " \
          "to get the viewer's sponsorship back even if it has been cancelled.", required: false, default_value: true
      end

      sig { params(active_only: T::Boolean).returns(T.nilable(Promise[::Sponsorship])) }
      def sponsorship_for_viewer_as_sponsor(active_only: true)
        viewer = @context[:viewer]
        return unless viewer

        sponsorship = viewer.sponsorship_as_sponsor_for(@object)
        return unless sponsorship

        sponsorship.async_hide_from_user?(viewer).then do |hide_from_user|
          next if hide_from_user

          sponsorship if sponsorship.active? || !active_only
        end
      end

      field(:sponsorship_for_viewer_as_sponsorable, Objects::Sponsorship,
        description: "The sponsorship from this user/organization to the viewer; that is, the sponsorship " \
          "you're receiving.",
        null: true,
      ) do
        argument :active_only, Boolean, "Whether to return the sponsorship only if it's still active. Pass false " \
          "to get the sponsorship back even if it has been cancelled.", required: false, default_value: true
      end

      sig { params(active_only: T::Boolean).returns(T.nilable(Promise[::Sponsorship])) }
      def sponsorship_for_viewer_as_sponsorable(active_only: true)
        viewer = @context[:viewer]
        return unless viewer

        @object.async_sponsorship_as_sponsor_for(viewer).then do |sponsorship|
          next unless sponsorship

          sponsorship.async_hide_from_user?(viewer).then do |hide_from_user|
            next if hide_from_user

            sponsorship if sponsorship.active? || !active_only
          end
        end
      end

      field(:sponsorships_as_maintainer, Connections::Sponsorship, connection: true, null: false,
        description: "The sponsorships where this user or organization is the maintainer receiving the funds.",
      ) do
        argument :include_private, Boolean,
          "Whether or not to include private sponsorships in the result set", required: false,
          default_value: false
        argument :order_by, Inputs::SponsorshipOrder,
          "Ordering options for sponsorships returned from this connection. If left blank, the sponsorships will " \
          "be ordered based on relevancy to the viewer.", required: false
        argument :active_only, Boolean, "Whether to include only sponsorships that are active right now, versus " \
          "all sponsorships this maintainer has ever received.", required: false, default_value: true
      end

      sig do
        params(
          include_private: T::Boolean,
          order_by: T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })),
          active_only: T::Boolean,
        ).returns(Promise[T::Array[::Sponsorship]])
      end
      def sponsorships_as_maintainer(include_private: false, order_by: nil, active_only: true)
        Platform::Loaders::SponsorshipsAsSponsorable.load(@object.id,
          viewer: @context[:viewer],
          include_private: include_private,
          order_by: order_by,
          active_only: active_only,
        ).then do |sponsorships|
          ArrayWrapper.new(sponsorships || [])
        end
      end

      field(:sponsorships_as_sponsor, Connections::Sponsorship, connection: true, null: false,
        description: "The sponsorships where this user or organization is the funder.",
      ) do
        argument :order_by, Inputs::SponsorshipOrder,
          "Ordering options for sponsorships returned from this connection. If left blank, the sponsorships will " \
          "be ordered based on relevancy to the viewer.", required: false
        argument :maintainer_logins, [String], "Filter sponsorships returned to those for the specified " \
          "maintainers. That is, the recipient of the sponsorship is a user or organization with one of " \
          "the given logins.", required: false
        argument :active_only, Boolean, "Whether to include only sponsorships that are active right now, versus " \
          "all sponsorships this sponsor has ever made.", required: false, default_value: true
      end

      sig do
        params(
          order_by: T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })),
          maintainer_logins: T::Array[String],
          active_only: T::Boolean,
        ).returns(Promise[T::Array[::Sponsorship]])
      end
      def sponsorships_as_sponsor(order_by: nil, maintainer_logins: [], active_only: true)
        valid_maintainer_logins = maintainer_logins.reject(&:blank?)
        sponsorables_promise = if valid_maintainer_logins.any?
          Loaders::ActiveRecord.load_all(::User, valid_maintainer_logins, column: :login)
        else
          Promise.resolve([])
        end
        sponsorables_promise.then do |sponsorables|
          Platform::Loaders::SponsorshipsAsSponsor.load(@object.id,
            viewer: @context[:viewer],
            order_by: order_by,
            sponsorable_ids: sponsorables.compact.map(&:id).compact,
            active_only: active_only,
          ).then do |sponsorships|
            ArrayWrapper.new(sponsorships || [])
          end
        end
      end

      DEFAULT_ACTIVITY_ORDER = { field: "timestamp", direction: "DESC" }

      field :sponsors_activities, Connections.define(Objects::SponsorsActivity),
        description: "Events involving this sponsorable, such as new sponsorships.", null: false, connection: true do
          argument :period, Enums::SponsorsActivityPeriod,
            "Filter activities returned to only those that occurred in the most recent specified time period. Set " \
              "to ALL to avoid filtering by when the activity occurred. Will be ignored if `since` or `until` is " \
              "given.", required: false, default_value: :month
          argument :since, Scalars::DateTime,
            "Filter activities to those that occurred on or after this time.", required: false
          argument :until, Scalars::DateTime,
            "Filter activities to those that occurred before this time.", required: false
          argument :order_by, Inputs::SponsorsActivityOrder,
            "Ordering options for activity returned from the connection.", required: false,
            default_value: DEFAULT_ACTIVITY_ORDER
          argument :actions, [Enums::SponsorsActivityAction], "Filter activities to only the specified actions.",
            required: false, default_value: []
          argument :include_as_sponsor, Boolean, "Whether to include those events where this sponsorable acted as " \
            "the sponsor. Defaults to only including events where this sponsorable was the recipient of a sponsorship.",
            required: false, default_value: false
          argument :include_private, Boolean,
            "Whether or not to include private activities in the result set. Defaults to including public and "\
            "private activities.", required: false, default_value: true
        end

      sig do
        params(
          period: T.nilable(Symbol),
          since: T.nilable(T.any(Time, DateTime)),
          order_by: T.any(Inputs::SponsorsActivityOrder, { field: String, direction: String }),
          actions: T::Array[String],
          include_as_sponsor: T::Boolean,
          include_private: T::Boolean,
          arguments: T.untyped,
        ).returns(ActiveRecord::Relation)
      end
      def sponsors_activities(
        period: nil,
        since: nil,
        order_by: DEFAULT_ACTIVITY_ORDER,
        actions: [],
        include_as_sponsor: false,
        include_private: true,
        **arguments
      )
        field = order_by[:field]
        direction = order_by[:direction]
        base_query = if include_as_sponsor
          SponsorsActivity.for_sponsorable_or_sponsor(@object)
        else
          @object.sponsors_activities
        end
        base_query = base_query.with_currently_public_sponsorship unless include_private

        activities = base_query.visible_to(@context[:viewer]).order("sponsors_activities.#{field} #{direction}")

        # `until` is a reserved word in Ruby so can't have `until` as a named parameter, have to get it from
        # `arguments` hash:
        until_time = arguments[:until]

        if since || until_time
          if since
            activities = activities.since(since)
          end

          if until_time
            activities = activities.until(until_time)
          end
        elsif period
          activities = activities.for_period(period)
        end

        activities = activities.with_actions(actions) if actions.present?
        activities
      end

      field :monthly_estimated_sponsors_income_in_cents, Integer,
        visibility: {
          internal: { environments: [:enterprise] },
          public: { environments: [:dotcom] },
        },
        description: "The estimated monthly GitHub Sponsors income for this user/organization in cents (USD).",
        null: false

      sig { returns Promise[Integer] }
      def monthly_estimated_sponsors_income_in_cents
        @object.async_total_monthly_pledged_in_dollars_visible_to(@context[:viewer]).then do |total|
          total.cents
        end
      end

      field :estimated_next_sponsors_payout_in_cents, Integer,
        visibility: {
          internal: { environments: [:enterprise] },
          public: { environments: [:dotcom] },
        },
        description: "The estimated next GitHub Sponsors payout for this user/organization in cents (USD).",
        null: false

      sig { returns Promise[Integer] }
      def estimated_next_sponsors_payout_in_cents
        @object.async_estimated_next_sponsors_payout_in_cents_visible_to(@context[:viewer]).then do |payout|
          payout.cents
        end
      end
    end
  end
end
