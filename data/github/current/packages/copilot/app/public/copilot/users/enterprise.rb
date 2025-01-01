# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Enterprise
      extend T::Helpers

      include Copilot::Users::Signatures
      include GitHub::Memoizer
      include GitHub::ResilienceMixin

      abstract!

      sig { override.returns(T::Boolean) }
      def is_partner_user?
        GitHub.tracer.in_span("copilot_user.is_partner_user?") do |_span|
          partner_org_ids.any?
        end
      rescue StandardError => e # rubocop:todo Lint/RescueException
        Copilot::ErrorReporter.report!(e, copilot_user: copilot_user_object)
        false
      end

      # The Copilot::Organization with the most restrictive public code
      # suggestion setting.
      sig { override.returns(T.nilable(Copilot::Organization)) }
      def copilot_organization
        copilot_organizations.first
      end

      sig { returns(T::Array[String]) }
      def organization_list
        copilot_authorizer_object.organization_list
      end

      # All Copilot organizations that this user has Copilot through. They are
      # sorted by most restrictive public code suggestion setting.
      sig { override.returns(T::Array[Copilot::Organization]) }
      def copilot_organizations
        @copilot_organizations ||= T.let(
          (
            orgs_using_copilot_for_business
          ).sort_by(&:public_code_suggestions_sorting),
          T.nilable(T::Array[Copilot::Organization])
        )
      end

      # All organizations with Copilot Enterprise that this user has Copilot through
      sig { override.returns(T::Array[Copilot::Organization]) }
      def copilot_enterprise_organizations
        @copilot_enterprise_organizations ||= T.let(
          begin
            orgs_using_copilot_for_business.select do |org|
              org.eligible_for_copilot_enterprise?
            end
          end,
          T.nilable(T::Array[Copilot::Organization])
        )
      end

      sig { returns(Promise[T::Boolean]) }
      def async_has_copilot_standalone_business?
        async_copilot_standalone_businesses.then do |businesses|
          !businesses.nil?
        end
      end

      sig { returns(T::Boolean) }
      def has_copilot_access_through_business?
        copilot_businesses_including_unaffiliated.any?
      end

      sig { override.returns(T::Boolean) }
      def has_copilot_standalone_business?
        async_has_copilot_standalone_business?.sync
      end

      sig { returns(T.any(Promise[NilClass], Promise[T.nilable(T::Array[Copilot::Business])])) }
      def async_copilot_standalone_businesses
        customer_promises = user_businesses_including_unaffiliated.map(&:async_customer)
        Promise.all(customer_promises).then do
          copilot_standalone_businesses
        end
      end

      sig { override.returns(T.nilable(T::Array[Copilot::Business])) }
      memoize def copilot_standalone_businesses
        # a user can theoretically belong to any number of standalone businesses
        # So, first grab all businesses to which they belong
        copilot_businesses = user_object.feature_flag_enabled_or_raise?(:copilot_standalone_businesses_seat_assignment_based) ? async_standalone_businesses_using_copilot_for_business.sync : user_businesses_including_unaffiliated.map { |biz| Copilot::Business.new(biz) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        # They arent a member of any businesses
        return if copilot_businesses.empty?

        # Next, determine if any of the businesses are standalone
        standalone_copilot_businesses = copilot_businesses.inject([]) do |memo, copilot_biz|
          memo << copilot_biz if copilot_biz.copilot_standalone?
          memo
        end

        # Again, return nil if they aren't a member of any standalone businesses
        return if standalone_copilot_businesses.empty?

        # These are the user's standalone businesses
        standalone_copilot_businesses
      end

      sig { override.returns(T.nilable(Copilot::Business)) }
      def copilot_business
        return nil if copilot_businesses.empty?
        copilot_businesses.first
      end

      sig { returns(T::Array[Copilot::Business]) }
      def copilot_businesses_including_unaffiliated
        copilot_businesses = user_businesses_including_unaffiliated.map do |business|
          copilot_business = Copilot::Business.new(business)
          copilot_business if Copilot::Seat.for_owner(business).where(assigned_user: user_object).any?
        end
        copilot_businesses.compact.uniq
      end

      # A user can be a member of multiple standalone businesses (access to Copilot only), and / or a member of multiple
      # businesses with a 'full' plan, including as an unaffiliated user with direct Copilot access.
      # If the user is a member of any number of standalone businesses, those will take precedence and be returned.
      # If not, we'll return all the business associated with organizations or the user themselves as an unaffiliated business user.
      sig { override.returns(T::Array[Copilot::Business]) }
      memoize def copilot_businesses
        return T.must(copilot_standalone_businesses) if has_copilot_standalone_business?

        org_bizs = copilot_organizations.map(&:copilot_business).compact.uniq
        # If the user is an unaffiliated business user, we also want to include those businesses
        # that have the copilot_business_user_assignment feature enabled.
        org_bizs | async_businesses_using_copilot_for_business.sync.select { |biz| biz if biz.feature_flag_enabled_or_raise?(:copilot_business_user_assignment) }.compact.uniq # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      # Get all businesses that a user gets Copilot access, this checks backward by copilot seat.
      # This includes:
      # - standalone businesses*
      # - businesses where they are an unaffiliated member with direct copilot access
      # - businesses with a 'full' plan (the standard business that people normally think of)
      # - business that are on active trials
      # * if the user is a standalone EMU user, they're unable to get seats from another business.
      sig { returns(T::Array[Copilot::Business]) }
      memoize def copilot_businesses_all
        return [] if has_cfi_access? && !has_limited_access?

        copilot_seats.map do |seat|
          owner = seat.seat_assignment.owner
          if owner.is_a?(::Business)
            Copilot::Business.new(owner)
          elsif owner.is_a?(::Organization) && owner.business.present?
            Copilot::Business.new(T.must(owner.business))
          end
        end.compact.uniq
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def copilot_seats
        copilot_public_user = Copilot::Public::User.new(user_object)
        copilot_public_user.copilot_seats
      end

      sig { override.returns(T::Boolean) }
      memoize def copilot_for_business_free?
        return true if copilot_businesses.any?(&:copilot_for_business_free?)
        copilot_organizations.any?(&:copilot_for_business_free?)
      end

      # this one is named similarly to the one below, but it has an important distinction: this lists the organizations that have
      # CfB enabled - not that have a Seat for this user necessarily
      sig { override.returns(T::Array[Copilot::Organization]) }
      def orgs_having_copilot_for_business
        user_object.organizations.select do |org|
          Copilot::Organization.new(org).has_copilot_for_business?
        end
      end

      sig { override.returns(T::Boolean) }
      def has_trial_organization?
        collect_metrics("copilot.has_trial_organization") do
          # avoid a possibly enormous `IN` clause by slicing the array into chunks of 1000
          org_ids = user_object.organization_ids
          return false if org_ids.nil? || org_ids.empty?
          org_ids.each_slice(1000).any? do |ids|
            Copilot::BusinessTrial.exists?(
              trialable_id: ids,
              trialable_type: "Organization"
            )
          end
        end
      end

      # Returns all organizations that this user has a Copilot seat through, or
      # the organization has the copilot_for_business feature flag enabled.
      sig { override.returns(T::Array[Copilot::Organization]) }
      memoize def orgs_using_copilot_for_business
        collect_metrics("copilot.orgs_using_copilot_for_business") do
          async_orgs_using_copilot_for_business.sync
        end
      end

      sig { override.returns(Promise[T::Array[Copilot::Organization]]) }
      def async_orgs_using_copilot_for_business
        return Promise.new.fulfill([]) if all_assignments_revoked?

        async_seats.then do |seats|
          async_seat_assignments.then do |assignments|
            next [] if seats.empty? && assignments.empty?

            org_promises = (seats + assignments).map(&:async_organization)

            Promise.all(org_promises).then do
              seat_orgs = seats.inject(Set.new) do |orgs, seat|
                next orgs if seat.organization.nil?

                org = T.must(seat.organization)

                # when determining policies for the user we don't want to include organizations which contain revoked seat assignments for the user
                next orgs if seat.seat_assignment&.access_revoked? && org.feature_flag_enabled_or_raise?(:copilot_exclude_revoked_assignments_for_policies) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

                orgs << Copilot::Organization.new(org)
                orgs
              end

              assignments.inject(seat_orgs) do |orgs, assignment|
                next orgs if assignment.organization.nil?

                org = T.must(assignment.organization)

                # when determining policies for the user we don't want to include organizations which contain revoked seat assignments for the user
                next orgs if assignment.access_revoked? && org.feature_flag_enabled_or_raise?(:copilot_exclude_revoked_assignments_for_policies) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

                orgs << Copilot::Organization.new(org)
                orgs
              end.to_a
            end
          end
        end
      end

      sig { returns(Promise[T::Array[Copilot::Business]]) }
      def async_businesses_using_copilot_for_business
        return Promise.new.fulfill([]) if all_assignments_revoked?

        async_seats.then do |seats|
          next [] if seats.empty?

          businesses = seats.inject(Set.new) do |businesses, seat|
            if seat.seat_assignment.nil?
              GitHub.logger.info("Seat has no seat assignment, skipping.",
                "code.namespace" => "async_businesses_using_copilot_for_business",
                "gh.copilot.seat" => seat,
                "gh.user.id" => user_object.id
              )
              next businesses
            end

            next businesses unless seat.owner.present?
            next businesses if seat.seat_assignment&.access_revoked? && seat.owner.feature_flag_enabled_or_raise?(:copilot_exclude_revoked_assignments_for_policies) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

            businesses << Copilot::Business.new(seat.owner.business) if seat.owner.is_a?(::Organization) && seat.owner.business.present?
            businesses << Copilot::Business.new(seat.owner) if seat.owner.is_a?(::Business)
            businesses
          end.uniq.to_a

          next businesses
        end
      end

      sig { returns(Promise[T::Array[Copilot::Business]]) }
      def async_standalone_businesses_using_copilot_for_business
        async_enterprise_team_seat_assignments.then do |assignments|
          next [] if assignments.empty?

          assignments.inject(Set.new) do |businesses, assignment|
            next businesses unless assignment.owner.present?
            businesses << Copilot::Business.new(assignment.owner.business) if assignment.owner.is_a?(::Organization) && assignment.owner.business.present?
            businesses << Copilot::Business.new(assignment.owner) if assignment.owner.is_a?(::Business)
            businesses
          end.uniq.to_a
        end
      end

      sig { returns(Promise[T::Hash[Symbol, T::Array[T.any(Copilot::Business, Copilot::Organization)]]]) }
      def async_businesses_and_orgs_using_copilot_for_business
        async_businesses_using_copilot_for_business.then do |businesses|
          async_orgs_using_copilot_for_business.then do |orgs|
            { businesses: businesses, organizations: orgs }
          end
        end
      end

      sig do
        returns(
          Promise[Copilot::Types::CollatedCopilotForBusinessConfigurations]
        )
      end
      def async_collated_copilot_for_business_configurations
        async_businesses_and_orgs_using_copilot_for_business.then do |businesses_and_orgs|
          businesses = businesses_and_orgs[:businesses]
          orgs = businesses_and_orgs[:organizations]

          configs = []
          promises = []
          if businesses.present?
            biz_ids = businesses.map(&:id)
            relation = Copilot::Configuration.where(configurable: biz_ids, configurable_type: "Business")
            promises << Platform::Loaders::ActiveRecord.load_relation(relation).then do |biz_config|
              biz_config.each do |conf|
                configs << { business: businesses.find { |biz| biz.id == conf.configurable_id }, config: conf }
              end
            end
          end

          if orgs.present?
            relation = Copilot::Configuration.where(configurable: orgs, configurable_type: "Organization")
            promises << Platform::Loaders::ActiveRecord.load_relation(relation).then do |org_config|
              org_config.each do |conf|
                configs << { organization: orgs.find { |org| org.id == conf.configurable_id }, config: conf }
              end
            end
          end

          Promise.all(promises).then do
            Promise.resolve(configs)
          end
        end
      end

      sig { params(include_revoked: T::Boolean).returns(Promise[T::Array[Copilot::SeatAssignment]]) }
      def async_all_seat_assignments(include_revoked: false)
        extra_conditions = if include_revoked
          {}
        else
          { pending_cancellation_date: nil }
        end

        relation = Copilot::SeatAssignment.where(
          assignable_id: user_object.team_ids,
          assignable_type: "Team",
          **extra_conditions
        )
        .or(
          Copilot::SeatAssignment.where(
            assignable_id: user_object.organization_ids,
            assignable_type: "Organization",
            **extra_conditions
          )
        ).or(
          # this REALLY shouldn't happen because the seat is created almost immediately
          Copilot::SeatAssignment.where(
            assignable_id: user_object.id,
            assignable_type: "User",
            **extra_conditions
          )
        )

        enterprise_team_ids = async_enterprise_team_ids.sync

        relation = relation.or(
          Copilot::SeatAssignment.where(
            assignable_id: enterprise_team_ids,
            assignable_type: "EnterpriseTeam",
            **extra_conditions
          )
        ) unless enterprise_team_ids.empty?

        if user_object.feature_flag_enabled?(:business_teams_in_seat_assignments_query, default: false)
          business_team_ids = Orgs.domain.teams.business_team_ids_for_user_id(user_object.id)
          relation = relation.or(Copilot::SeatAssignment.where(
            owner_id: user_object.business_ids,
            owner_type: "Business",
            assignable_type: "BusinessTeam",
            assignable_id: business_team_ids,
            **extra_conditions
          )) unless business_team_ids.empty?
        end

        Platform::Loaders::ActiveRecord.load_relation(relation)
      end

      sig { override.returns(Promise[T::Array[Copilot::SeatAssignment]]) }
      def async_seat_assignments
        GitHub.tracer.in_span("copilot.enterprise.async_seat_assignments") do |_span|
          GitHub.dogstats.distribution_time("copilot.enterprise.async_seat_assignments.latency") do
            async_all_seat_assignments(include_revoked: false)
          end
        end
      end

      sig { returns(Promise[T::Array[Copilot::SeatAssignment]]) }
      def async_revokable_seat_assignments
        GitHub.tracer.in_span("copilot.enterprise.async_revokable_seat_assignments") do |_span|
          GitHub.dogstats.distribution_time("copilot.enterprise.async_revokable_seat_assignments.latency") do
            async_all_seat_assignments(include_revoked: true)
          end
        end
      end

      sig { returns(Promise[T::Array[Copilot::SeatAssignment]]) }
      def async_enterprise_team_seat_assignments
        GitHub.tracer.in_span("copilot.enterprise.async_enterprise_team_seat_assignments") do |_span|
          relation = Copilot::SeatAssignment.where(
              assignable_id: EnterpriseTeam.all_visible_team_ids_for(user_object),
              assignable_type: "EnterpriseTeam" # only standalones should have this type of seat assignment
            )

          Platform::Loaders::ActiveRecord.load_relation(relation)
        end
      end

      sig { override.returns(Promise[T::Array[Copilot::Seat]]) }
      def async_seats
        GitHub.tracer.in_span("copilot.enterprise.async_seats") do |_span|
          with_database_error_fallback(fallback: Promise.resolve([])) do
            relation = Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: user_object.id)
            Platform::Loaders::ActiveRecord.load_relation(relation)
          end
        end
      end

      sig { override.returns(T::Array[Copilot::Organization]) }
      def partner_orgs
        ::Organization.find(partner_org_ids).map do |org|
          Copilot::Organization.new(org)
        end
      end

      sig { returns(T::Array[Integer]) }
      def partner_org_ids
        return [] unless FeatureFlag.vexi.exists_or_raise?(:copilot_for_partners) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

        # We're never going to have more than one or two hundred partner orgs, so it's OK to load the ids into memory.
        actor_ids_by_class = GitHub::VexiActor.actor_ids_by_class_or_raise(:copilot_for_partners)
        partner_org_ids = (actor_ids_by_class.to_h[::Organization] || []).map(&:to_i)

        user_object.organization_ids & partner_org_ids
      end

      sig { returns(Promise[T::Array[Integer]]) }
      def async_enterprise_team_ids
        async_has_copilot_standalone_business?.then do |has_copilot_standalone_biz|
          next [] unless has_copilot_standalone_biz

          EnterpriseTeam.all_visible_team_ids_for(user_object)
        end
      end

      sig { returns(T::Array[Integer]) }
      def enterprise_team_ids
        async_enterprise_team_ids.sync
      end

      sig { override.returns(T::Boolean) }
      memoize def all_assignments_revoked?
        async_revokable_seat_assignments.sync.all?(&:access_revoked?)
      end

      private

      sig { returns T::Array[::Business] }
      memoize def user_businesses_including_unaffiliated
        # For enterprise managed users who are guest collaborators,
        # we should only return their enterprise_managed_business
        if user_object.is_enterprise_managed? && user_object.guest_collaborator?
          return [user_object.enterprise_managed_business].compact
        end
        user_object.businesses(include_unaffiliated: true).to_a
      end
    end
  end
end
