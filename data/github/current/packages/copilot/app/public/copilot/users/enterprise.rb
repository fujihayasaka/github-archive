# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Enterprise
      extend T::Helpers
      extend T::Sig

      include Copilot::Users::Signatures
      include GitHub::Memoizer

      abstract!

      sig { override.returns(T::Boolean) }
      def is_partner_user?
        GitHub.tracer.in_span("copilot_user.is_partner_user?") do |_span|
          partner_org_ids.any?
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
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

      sig { override.returns(T::Boolean) }
      def has_copilot_standalone_business?
        !copilot_standalone_businesses.nil?
      end

      sig { override.returns(T.nilable(T::Array[Copilot::Business])) }
      memoize def copilot_standalone_businesses
        # a user can theoretically belong to any number of standalone businesses
        # So, first grab all businesses to which they belong
        businesses = user_object.businesses(include_unaffiliated: true)

        # They arent a member of any businesses
        return if businesses.empty?

        # Next, determine if any of the businesses are standalone
        copilot_businesses = businesses.inject([]) do |memo, biz|
          copilot_biz = Copilot::Business.new(biz)
          memo << copilot_biz if copilot_biz.copilot_standalone?
          memo
        end

        # Again, return nil if they aren't a member of any standalone businesses
        return if copilot_businesses.empty?

        # These are the user's standalone businesses
        copilot_businesses
      end

      sig { override.returns(T.nilable(Copilot::Business)) }
      def copilot_business
        return nil if copilot_businesses.empty?
        copilot_businesses.first
      end

      # A user can be a member of multiple standalone businesses (access to Copilot only), and / or a member of multiple
      # businesses with a 'full' plan.
      # If the user is a member of any number of standalone businesses, those will take precedence and be returned.
      # If not, we'll return all the business associated with organizations.
      sig { override.returns(T::Array[Copilot::Business]) }
      memoize def copilot_businesses
        return T.must(copilot_standalone_businesses) if has_copilot_standalone_business?
        copilot_organizations.map(&:copilot_business).compact.uniq
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
          user_object.organization_ids.each_slice(1000).any? do |ids|
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
        async_seats.then do |seats|
          async_seat_assignments.then do |assignments|
            next [] if seats.empty? && assignments.empty?

            seat_orgs = seats.inject(Set.new) do |orgs, seat|
              orgs << Copilot::Organization.new(T.must(seat.organization)) unless seat.organization.nil? # this shouldn't happen, but it does
              orgs
            end

            assignments.inject(seat_orgs) do |orgs, assignment|
              orgs << Copilot::Organization.new(T.must(assignment.organization)) unless assignment.organization.nil? # this shouldn't happen, but it does
              orgs
            end.to_a
          end
        end
      end

      sig { returns(Promise[T::Array[Copilot::Business]]) }
      def async_businesses_using_copilot_for_business
        async_seat_assignments.then do |assignments|
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
        params(cached: T::Boolean).
        returns(
          Promise[Copilot::Types::CollatedCopilotForBusinessConfigurations]
        )
      end
      def async_collated_copilot_for_business_configurations(cached = true)
        cached_configs = nil
        unless GitHub.review_lab? && cached
          cached_configs = Copilot.redis.hget("copilot:configs:#{user_object.id}", "configuration")
        end
        if cached_configs.nil?
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
              unless GitHub.review_lab? && cached
                Copilot.redis.hset("copilot:configs:#{user_object.id}", "configuration", configs.to_json(dangerously_allow_all_keys: true))
                Copilot.redis.expire("copilot:configs:#{user_object.id}", 5.seconds)
              end
              Promise.resolve(configs)
            end
          end
        else
          configs = JSON.parse(cached_configs, { symbolize_names: true })
          parsed_json = configs.map do |config|
            # JSON storing does funny things
            conf = {}
            if config[:organization].present?
              conf = { organization: config[:organization][:organization], config: config[:config][:configuration] }
            end

            if config[:business].present?
              conf = { business: config[:business][:business], config: config[:config][:configuration] }
            end
            conf
          end

          Promise.resolve(T.let(parsed_json, Copilot::Types::CollatedCopilotForBusinessConfigurations))
        end
      end

      sig { override.returns(Promise[T::Array[Copilot::SeatAssignment]]) }
      def async_seat_assignments
        GitHub.tracer.in_span("copilot.enterprise.async_seat_assignments") do |_span|
          team_ids = enterprise_team_ids

          relation = if team_ids.any?
            Copilot::SeatAssignment.where(
              assignable_id: team_ids,
              assignable_type: "EnterpriseTeam",
              pending_cancellation_date: nil,
            )
          else
            Copilot::SeatAssignment.where(
              assignable_id: user_object.team_ids,
              assignable_type: "Team",
              pending_cancellation_date: nil,
            ).or(
              Copilot::SeatAssignment.where(
                assignable_id: user_object.organization_ids,
                assignable_type: "Organization",
                pending_cancellation_date: nil,
              )
            ).or(
              # this REALLY shouldn't happen because the seat is created almost immediately
              Copilot::SeatAssignment.where(
                assignable_id: user_object.id,
                assignable_type: "User",
                pending_cancellation_date: nil,
              )
            )
          end

          Platform::Loaders::ActiveRecord.load_relation(relation)
        end
      end

      sig { override.returns(Promise[T::Array[Copilot::Seat]]) }
      def async_seats
        GitHub.tracer.in_span("copilot.enterprise.async_seats") do |_span|
          relation = Copilot::Seat.where(assigned_user_id: user_object.id)
          Platform::Loaders::ActiveRecord.load_relation(relation)
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
        feature = FlipperFeature.find_by(name: "copilot_for_partners")
        return [] unless feature

        # We're never going to have more than one or two hundred partner orgs, so it's OK to load the ids into memory
        partner_org_ids = (feature.actor_ids_by_class.to_h[::Organization] || []).map(&:to_i)

        user_object.organization_ids & partner_org_ids
      end

      sig  { returns(T::Array[Integer]) }
      def enterprise_team_ids
        return [] unless has_copilot_standalone_business?

        EnterpriseTeam.all_visible_team_ids_for(user_object)
      end
    end
  end
end
