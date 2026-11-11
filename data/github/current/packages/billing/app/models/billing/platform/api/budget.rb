# typed: strict
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class Budget
        include GitHub::Memoizer
        include Billing::Platform::Api::Utils

        # Schema
        # {
        #   "budget" =>
        #   {
        #     "key" =>
        #     {
        #       "customerId" => "1",
        #       "targetType"=> :CustomerResource,
        #       "targetId"=> "471549",
        #       "pricingTargetType"=>:SkuPricing,
        #       "pricingTargetId"=>"sku"
        #     },
        #     "targetAmount"=>99.9,
        #     "budgetLimitType"=>:PreventFurtherUsage,
        #     "budgetAlerting"=>
        #     {
        #       "willAlert"=>true,
        #       "recipientUserIds"=>["1"]
        #     },
        #   },
        #   "budgetState" =>
        #   {
        #     "isFullyFunded"=>false,
        #     "currentAmount"=>0.0,
        #     "targetAmount"=>99.9,
        #     "quantity"=>0.0,
        #     "thresholdMet"=>{
        #       "name"=>"75%",
        #       "minimumUsagePercentage"=>0.75,
        #       "alertable"=>true
        #     }
        #   }
        # }

        delegate :[], :[]=, to: :raw_budget

        sig { params(raw_budget: T::Hash[Symbol, T.untyped]).void }
        def initialize(raw_budget)
          @raw_budget = T.let(raw_budget.with_indifferent_access, T::Hash[Symbol, T.untyped])
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def raw_budget_hash
          @raw_budget
        end

        sig { returns(T.any(String, Integer)) }
        def customer_id
          raw_budget[:budget][:key][:customerId]
        end

        sig { returns(String) }
        def target_type
          if raw_budget[:budget][:key][:targetType].to_s == "OwningEntity"
            "Organization"
          else
            raw_budget[:budget][:key][:targetType].to_s
          end
        end

        sig { returns(T.any(Integer, String)) }
        def target_id
          raw_budget[:budget][:key][:targetId]
        end

        # We convert to a global ID so that our frontend is able to preload the target
        # when a user is editing budget. This functionality is only required for editing
        # Repo and Org scopes.
        sig { returns(T.nilable(T.any(String, Integer))) }
        def global_target_id
          klass = case target_type
          when REPOSITORY_TARGET
            Repository
          when ORGANIZATION_TARGET
            Organization
          else
            return target_id
          end
          klass.find_by(id: target_id)&.global_relay_id
        end

        sig { returns(T::Array[String]) }
        def alert_recipient_global_user_ids
          User.where(id: raw_budget[:budget][:budgetAlerting][:recipientUserIds]).map { |u| u.global_relay_id }
        end

        sig { returns(String) }
        def pricing_target_type
          raw_budget[:budget][:key][:pricingTargetType].to_s
        end

        sig { returns(String) }
        def pricing_target_id
          raw_budget[:budget][:key][:pricingTargetId]
        end

        sig { returns(String) }
        def product_name
          "billing_platform_#{pricing_target_type}"
        end

        sig { returns(T.nilable(Integer)) }
        def license_count
          raw_budget[:budget][:licenseCount] || raw_budget.dig(:budgetState, :targetLicenseCount)
        end

        sig { returns(T.nilable(Integer)) }
        def current_license_count
          raw_budget.dig(:budgetState, :currentLicenseCount)
        end

        sig { returns(Float) }
        def target_amount
          raw_budget[:budget][:targetAmount].to_f
        end

        sig { returns(String) }
        def budget_limit_type
          raw_budget[:budget][:budgetLimitType].to_s
        end

        sig { returns(T::Boolean) }
        def alert_enabled?
          !!raw_budget[:budget][:budgetAlerting][:willAlert]
        end

        sig { returns(T::Array[String]) }
        def alert_recipients_user_ids
          raw_budget[:budget][:budgetAlerting][:recipientUserIds] || []
        end

        sig { returns(T::Array[String]) }
        memoize def alert_recipient_user_logins
          User.where(id: alert_recipients_user_ids).pluck(:display_login)
        end

        sig { returns(T::Boolean) }
        def fully_funded?
          return true if license_budget_reached?
          !!raw_budget.dig(:budgetState, :isFullyFunded)
        end

        sig { returns(T::Boolean) }
        def license_budget_reached?
          target = license_count
          current = current_license_count
          return false if target.nil? || current.nil? || target <= 0

          current >= target
        end

        sig { returns(Float) }
        def current_amount
          raw_budget.dig(:budgetState, :currentAmount).to_f
        end

        sig { returns(T::Hash[Integer, T::Hash[String, T::Array[Integer]]]) }
        def multi_user_budget_thresholds
          raw_budget.dig(:budgetState, :budgetThresholds) || {}
        end

        sig { returns(T::Hash[Integer, T::Hash[String, Integer]]) }
        def multi_user_budget_threshold_summary
          raw_budget.dig(:budgetState, :budgetThresholdsSummary) || {}
        end

        sig { returns(T::Boolean) }
        def has_next_page?
          raw_budget[:hasNextPage]
        end

        sig { returns(Integer) }
        def current_percentage
          return 0 if target_amount.zero?

          ((current_amount / target_amount) * 100).floor
        end

        sig { returns(Float) }
        def quantity
          raw_budget.dig(:budgetState, :quantity).to_f
        end

        sig { returns(T.nilable(Integer)) }
        def month
          value = raw_budget.dig(:budgetState, :month)
          return nil if value.nil?
          value.to_i if value.respond_to?(:to_i) && value.to_s.match?(/\A\d+\z/)
        end

        sig { returns(T.nilable(Integer)) }
        def year
          value = raw_budget.dig(:budgetState, :year)
          return nil if value.nil?
          value.to_i if value.respond_to?(:to_i) && value.to_s.match?(/\A\d+\z/)
        end

        sig { returns(String) }
        def uuid
          raw_budget[:budget][:uuid].to_s
        end

        sig { returns(T::Boolean) }
        def exclude_cost_center_usage?
          wrapper = raw_budget[:budget][:excludeCostCenterUsage]
          # Handle protobuf BoolValue wrapper type which serializes as {"value": bool}
          wrapper.is_a?(Hash) ? !!wrapper[:value] : !!wrapper
        end

        sig { returns(T::Array[User]) }
        def alert_recipient_users
          User.where(id: alert_recipient_user_ids).to_a
        end

        sig { returns(T::Array[String]) }
        def alert_recipient_user_ids
          raw_budget[:budget][:budgetAlerting][:recipientUserIds]
        end

        sig { returns(T.nilable(T.any(::Billing::Types::Account, Repository, CostCenter, User))) }
        memoize def target
          case target_type
          when CUSTOMER_TARGET, ENTERPRISE_TARGET, MULTIUSERCUSTOMER_TARGET # remove enterprise when we remove enterprise budgets
            Customer.find_by(id: target_id)&.billable_owner
          when REPOSITORY_TARGET
            T.cast(Repositories.domain.by_id(target_id.to_i), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          when ORGANIZATION_TARGET
            Organization.find_by(id: target_id)
          when COSTCENTER_TARGET, MULTIUSERCOSTCENTER_TARGET
            # cost center is not an active record model, it is a billing platform "model"
            CostCenter.new(customer_id: customer_id.to_s, uuid: target_id.to_s)
          when USER_TARGET
            User.find_by(id: target_id)
          end
        end

        sig { returns(String) }
        def target_name
          case target = self.target
          when Business
            target.slug
          when Organization
            target.safe_profile_name
          when Repository
            target.name_with_display_owner
          when CostCenter
            target.name
          when User
            target.display_login
          end
        end

        sig { returns(T.nilable(::Billing::Types::Account)) }
        def owner
          target = self.target
          case target
          when Repository
            target.owner
          when CostCenter
            target.billable_owner
          else
            target
          end
        end

        sig { params(context: T.any(::Billing::Types::Account, Repository, CostCenter)).returns(T::Boolean) }
        def visible_to?(context)
          case context
          when Repository
            context == target
          when Organization
            budget_visible_to_org?(context, target)
          when Business
            budget_visible_to_business?(context, target)
          when User
            (alert_recipients_user_ids.include? context.id.to_s) || (context == owner)
          else
            false
          end
        end

        sig { params(options: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
        def as_json(options = {})
          json = {
            targetType: target_type,
            targetAmount: target_amount,
            licenseCount: license_count,
            currentLicenseCount: current_license_count,
            budgetLimitType: budget_limit_type,
            currentAmount: current_amount,
            targetName: target_name,
            alertEnabled: alert_enabled?,
            alertRecipientUserIds: alert_recipients_user_ids,
            alertRecipientUserLogins: alert_recipient_user_logins,
            targetId: global_target_id,
            pricingTargetId: pricing_target_id,
            pricingTargetType: pricing_target_type,
            uuid: uuid,
            excludeCostCenterUsage: exclude_cost_center_usage?
          }

          if is_multi_user_budget(target_type: target_type)
            json[:budgetThresholdsSummary] = multi_user_budget_threshold_summary
          end

          json
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_edit_json
          as_json.merge({
            alertEnabled: alert_enabled?,
            alertRecipientUserIds: alert_recipient_global_user_ids,
            pricingTargetId: pricing_target_id,
            pricingTargetType: pricing_target_type,
            excludeCostCenterUsage: exclude_cost_center_usage?
          })
        end

        sig { returns(String) }
        def slug
          [uuid, target_amount].join("-")
        end

        sig { returns(Integer) }
        def threshold_percentage
          (raw_budget.dig(:budgetState, :thresholdMet, :minimumUsagePercentage).to_f).floor
        end

        sig { returns(T::Boolean) }
        def threshold_alertable?
          raw_budget.dig(:budgetState, :thresholdMet, :alertable)
        end

        private

        sig { returns(T::Hash[Symbol, T.untyped])  }
        attr_reader :raw_budget

        sig do
          params(
            organization: Organization,
            target: T.nilable(T.any(::Billing::Types::Account, CostCenter, Repository))
          ).returns(T::Boolean)
        end
        def budget_visible_to_org?(organization, target)
          case target
          when Business
            target == organization.business
          when Organization
            organization == target
          when Repository
            organization == target.owner
          else
            false
          end
        end

        sig do
          params(
            business: Business,
            target: T.nilable(T.any(::Billing::Types::Account, CostCenter, Repository))
          ).returns(T::Boolean)
        end
        def budget_visible_to_business?(business, target)
          case target
          when Business
            business == target
          when Organization
            business == target.business
          when Repository
            business == target.owner&.business
          when CostCenter
            business == target.billable_owner
          else
            false
          end
        end
      end
    end
  end
end
