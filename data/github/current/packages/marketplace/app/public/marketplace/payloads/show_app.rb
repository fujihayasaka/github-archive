# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class ShowApp
      include UrlHelpers
      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::TextHelper
      include MoneyHelper
      include PlanHelper
      include GitHub::Memoizer

      sig { returns(Marketplace::Listing) }
      attr_reader :marketplace_listing
      alias listing marketplace_listing

      sig { override.returns(T.nilable(User)) }
      attr_reader :current_user

      sig { params(marketplace_listing: Marketplace::Listing, current_user: T.nilable(User)).void }
      def initialize(marketplace_listing:, current_user:)
        @marketplace_listing = marketplace_listing
        @current_user = current_user
      end

      sig do
        returns({
          listing: Marketplace::Types::SerializedAppListing,
          screenshots: T::Array[Marketplace::Types::SerializedScreenshot],
          plan_info: Marketplace::Types::PlanInfo,
          supported_languages: T::Array[String],
          verified_domain: T.nilable(String),
          user_can_edit: T::Boolean,
          customers: T::Array[{ displayLogin: String, image: T.nilable(String) }]
        })
      end
      def call
        {
          listing: Marketplace::Serializers::App.serialize_model(marketplace_listing, current_user: current_user),
          screenshots: screenshots,
          plan_info: plan_info,
          supported_languages: T.cast(marketplace_listing.languages.map { |l| l.name }, T::Array[String]),
          verified_domain: verified_domain,
          user_can_edit: marketplace_listing.allowed_to_edit?(current_user),
          customers: customers,
        }
      end

      private

      sig { returns(T::Array[Marketplace::Types::SerializedScreenshot]) }
      def screenshots
        marketplace_listing.screenshots.includes(:listing).map do |screenshot|
          {
            id: T.must(screenshot.id),
            src: screenshot.storage_external_url(current_user),
            caption: screenshot.caption,
            alt_text: screenshot.alt_text,
          }
        end
      end

      sig { returns(Marketplace::Types::PlanInfo) }
      def plan_info
        {
          any_account_eligible_for_free_trial: any_account_eligible_for_free_trial,
          can_sign_end_user_agreement: can_sign_end_user_agreement,
          emu_owner_but_not_admin: emu_owner_but_not_admin,
          end_user_agreement: serialized_agreement,
          free_trial_length: T.cast(pluralize(Billing::Subscription::FREE_TRIAL_LENGTH / (60 * 60 * 24), "day"), String),
          free_trials_used: free_trials_used,
          installation_url_requirement_met: marketplace_listing.installation_url_requirement_met?,
          is_buyable: (!viewer_has_purchased || !all_orgs_purchased) && marketplace_listing.installation_url_requirement_met?,
          is_logged_in: T.cast(current_user.present?, T::Boolean),
          is_regular_emu_user: is_regular_emu_user,
          is_user_billed_monthly: is_user_billed_monthly,
          listing_by_github: marketplace_listing.by_github?,
          order_preview: { quantity: order_preview&.quantity },
          organizations: organizations.map do |org|
            {
              display_login: org.display_login,
              has_extensibility_access: extension_access_by_org_id[org.id] || false,
              image: org.primary_avatar_url(48)
            }
          end,
          plans: serialized_plans,
          selected_account: selected_account&.display_login,
          selected_plan_id: selected_plan&.global_relay_id,
          subscription_item: { on_free_trial: subscription_item&.on_free_trial? },
          support_email: marketplace_listing.support_email,
          user_can_edit_listing: marketplace_listing.allowed_to_edit?(current_user),
          viewer_free_trial_days_left: viewer_free_trial_days_left,
          viewer_has_purchased: viewer_has_purchased,
          any_orgs_purchased: any_orgs_purchased,
          viewer_billed_organizations: viewer_billed_organizations.map(&:display_login),
          viewer_has_purchased_for_all_organizations: viewer_has_purchased_for_all_organizations,
          installed_for_viewer: marketplace_listing.installed_for?(current_user),
          plan_id_by_login: plan_id_by_login,
          current_user: serialized_current_user,
        }
      end

      sig { returns(T::Array[{ displayLogin: String, image: T.nilable(String) }]) }
      def customers
        T.unsafe(marketplace_listing.featured_organizations_non_spammy).approved.includes(:organization).map do |featured_org|
          org = featured_org.organization
          next unless org

          { displayLogin: org.display_login, image: org.primary_avatar_url(48) }
        end.compact
      end

      sig { returns(T.nilable({ display_login: String, has_extensibility_access: T::Boolean, image: T.nilable(String) })) }
      def serialized_current_user
        return nil unless current_user.present?

        {
          display_login: T.must(current_user).display_login,
          has_extensibility_access: Copilot::User.new(T.must(current_user)).copilot_extensions_enabled?,
          image: T.must(current_user).primary_avatar_url(48)
        }
      end

      sig { returns(T.nilable(String)) }
      def verified_domain
        return unless marketplace_listing.owner&.organization?

        T.cast(marketplace_listing.owner, Organization).email_eligible_domain_urls(include_approved: false)&.first
      end

      sig { returns(T::Array[Marketplace::Types::Plan]) }
      def serialized_plans
        plans = marketplace_listing
                  .listing_plans
                  .with_published_state
                  .order("marketplace_listing_plans.yearly_price_in_cents")
                  .first(Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING)

        plans.map do |plan|
          {
            name: plan.name,
            description: plan.description,
            yearly_price_in_cents: plan.yearly_price_in_cents,
            monthly_price_in_cents: plan.monthly_price_in_cents,
            per_unit: plan.per_unit,
            unit_name: plan.unit_name,
            has_free_trial: plan.has_free_trial,
            direct_billing: plan.direct_billing,
            id: plan.global_relay_id,
            is_paid: plan.paid?,
            price: casual_currency(is_user_billed_monthly ? plan.monthly_price_in_dollars : plan.yearly_price_in_dollars),
            for_organizations_only: plan.for_organizations_only?,
            for_users_only: plan.for_users_only?,
            bullets: plan.bullets.order(:id).first(Marketplace::ListingPlanBullet::BULLET_LIMIT_PER_LISTING_PLAN).pluck(:value),
          }
        end
      end

      sig { returns(T::Array[Organization]) }
      memoize def organizations
        return [] unless current_user.present?

        T.must(current_user).owned_organizations.order(:id).includes(:business).preload(:plan_subscription).records
      end

      sig { returns(T.nilable(Marketplace::OrderPreview)) }
      memoize def order_preview
        marketplace_listing.marketplace_order_previews.where(user: current_user).first
      end

      sig { returns(T.nilable(Billing::SubscriptionItem)) }
      memoize def subscription_item
        return nil unless current_user.present?

        T.must(current_user).subscription_item_for_marketplace_listing(marketplace_listing)
      end

      sig { returns(T::Boolean) }
      memoize def is_regular_emu_user
        return false unless current_user.present?

        T.must(current_user).is_enterprise_managed? && !T.must(current_user).is_emu_admin? && !T.must(current_user).is_emu_org_owner?
      end

      sig { returns(T::Boolean) }
      memoize def can_sign_end_user_agreement
        marketplace_listing.can_sign_end_user_agreement?(current_user, agreement: end_user_agreement)
      end

      sig { returns(T::Boolean) }
      memoize def emu_owner_but_not_admin
        user = current_user

        return false unless user.present?
        return false unless user.is_emu_org_owner?
        return false unless selected_plan&.paid?

        !user.is_emu_admin?
      end

      sig { returns(T::Boolean) }
      memoize def is_buyable
        (!viewer_has_purchased || !all_orgs_purchased) && marketplace_listing.installation_url_requirement_met?
      end

      sig { returns(T.nilable(Marketplace::ListingPlan)) }
      memoize def selected_plan
        if order_preview && T.must(order_preview).listing_plan&.can_user_see?(current_user)
          T.must(order_preview).listing_plan
        else
          marketplace_listing.default_plan
        end
      end

      sig { returns(T::Hash[Organization, T.nilable(Billing::SubscriptionItem)]) }
      memoize def subscription_items_by_org
        organizations.each_with_object({}) do |org, hash|
          business = org.business

          hash[org] = if business.present? && business.self_serve_payment?
            business.subscription_item_for_marketplace_listing(marketplace_listing, organization: org)
          else
            org.subscription_item_for_marketplace_listing(marketplace_listing)
          end
        end
      end

      sig { returns(T::Boolean) }
      memoize def viewer_has_purchased
        subscription_item.present?
      end

      sig { returns(T::Boolean) }
      memoize def all_orgs_purchased
        T.cast(current_user.present?, T::Boolean) && organizations.all? { |org| subscription_items_by_org[org].present? }
      end

      sig { returns(T::Boolean) }
      memoize def any_account_eligible_for_free_trial
        eligible_for_free_trial = !current_user || T.must(current_user).get_plan_subscription_or_null_plan.eligible_for_free_trial_on_listing?(marketplace_listing)
        any_org_eligible_for_free_trial = organizations.any? { |org| org.get_plan_subscription_or_null_plan.eligible_for_free_trial_on_listing?(marketplace_listing) }

        eligible_for_free_trial || any_org_eligible_for_free_trial
      end

      sig { returns(T.nilable(User)) }
      def selected_account
        un_billed_orgs = if current_user
          organizations.map do |org|
            item = subscription_items_by_org[org]
            plan = item ? item.subscribable : nil
            org unless plan
          end.compact
        else
          []
        end

        order_preview_account = order_preview&.account || order_preview&.user
        order_preview_account_has_not_purchased = order_preview_account &&
          un_billed_orgs.map(&:display_login).include?(order_preview_account.display_login) &&
          (current_user&.display_login == order_preview_account.display_login ? !viewer_has_purchased : true)


        if order_preview_account_has_not_purchased
          order_preview_account
        elsif viewer_has_purchased
          un_billed_orgs.first
        else
          current_user
        end
      end

      sig { returns(T::Boolean) }
      memoize def is_user_billed_monthly
        current_user.try(:plan_duration) != "year"
      end

      sig { returns(T.nilable(Marketplace::Agreement)) }
      memoize def end_user_agreement
        Marketplace::Agreement.latest_for_end_users
      end

      sig { returns(T.nilable(Integer)) }
      memoize def viewer_free_trial_days_left
        return unless selected_plan&.has_free_trial? && viewer_has_purchased

        if subscription_item&.free_trial_ends_on
          (subscription_item&.free_trial_ends_on.to_date - GitHub::Billing.today).to_i
        else
          0
        end
      end

      sig { returns(T::Boolean) }
      memoize def free_trials_used
        return false unless selected_plan&.has_free_trial? && viewer_has_purchased && all_orgs_purchased

        !viewer_free_trial_days_left&.positive? && organizations.none? do |org|
          org_subscription_item = subscription_items_by_org[org]
          org_free_trial_end = org_subscription_item&.free_trial_ends_on || GitHub::Billing.today
          (org_free_trial_end.to_date - GitHub::Billing.today).to_i.positive?
        end
      end

      sig do
        returns(T.nilable({
          html: String,
          id: Integer,
          name: T.nilable(String),
          user_signed_at: T.nilable(ActiveSupport::TimeWithZone),
          version: String
        }))
      end
      def serialized_agreement
        return unless end_user_agreement
        signature = T.must(end_user_agreement).signatures.for_user(current_user).latest.first if current_user

        {
          html: Platform::Helpers::MarketplaceListingContent.html_for(end_user_agreement, :body, { current_user: current_user }),
          id: T.must(end_user_agreement&.id),
          name: T.must(end_user_agreement).name,
          user_signed_at: signature&.created_at,
          version: T.must(end_user_agreement&.version),
        }
      end

      sig { returns(T::Array[Organization]) }
      memoize def owned_orgs
        current_user = self.current_user
        return [] unless current_user.present?

        current_user.owned_organizations.includes(:business).to_a
      end

      sig { returns(T::Array[Organization]) }
      memoize def billed_orgs
        current_user = self.current_user
        return [] unless current_user.present?

        marketplace_listing_id = T.must(marketplace_listing.id)

        user_billed_orgs = current_user.billed_organizations_for_marketplace_listing(marketplace_listing_id).to_a
        businesses = owned_orgs.map(&:business).uniq.compact
        business_billed_orgs = businesses.flat_map do |business|
          business.organizations_for_marketplace_listing(marketplace_listing_id, current_user)
        end

        (user_billed_orgs + business_billed_orgs).uniq
      end

      sig { returns(T::Array[Organization]) }
      memoize def viewer_billed_organizations
        return [] unless current_user.present?

        billed_orgs.take(100)
      end

      sig { returns(T.nilable(Marketplace::ListingPlan)) }
      memoize def viewer_active_plan
        return unless current_user

        T.must(current_user)
          .active_subscription_items
          .for_marketplace_listing_plans(marketplace_listing.listing_plans.pluck(:id))
          .first&.subscribable
      end

      sig { returns(T::Boolean) }
      memoize def any_orgs_purchased
        return false unless current_user.present?

        Promise.all(viewer_billed_organizations.map { |org| org.async_active_listing_plan(marketplace_listing.slug) }).sync

        sub_items_by_org = viewer_billed_organizations.each_with_object({}) do |org, hash|
          item = if org.business.present? && T.must(org.business).self_serve_payment?
            T.must(org.business).subscription_item_for_marketplace_listing(T.must(marketplace_listing.id), organization: org)
          else
            org.subscription_item_for_marketplace_listing(marketplace_listing)
          end
          hash[org] = item if item&.adminable_by?(current_user)
        end

        sub_items_by_org = sub_items_by_org.to_h

        GitHub::PrefillAssociations.prefill_associations(sub_items_by_org.values, [:subscribable], available_records: [current_user])
        Promise.all(sub_items_by_org.values.flat_map do |item|
          [item.async_authorization_required?(current_user), item.async_subscribable]
        end).sync

        sub_items_by_org.any?
      end

      sig { returns(T::Boolean) }
      memoize def viewer_has_purchased_for_all_organizations
        return false unless current_user.present?

        billed_orgs.map(&:id).to_set == owned_orgs.map(&:id).to_set
      end

      sig { returns(T::Hash[String, String]) }
      memoize def plan_id_by_login
        hash = {}
        return hash unless current_user.present?

        subscription_items_by_org.each do |org, subscription_item|
          next unless subscription_item&.subscribable

          hash[org.display_login] = subscription_item.subscribable.global_relay_id
        end

        if viewer_active_plan
          hash[T.must(current_user).display_login] = T.must(viewer_active_plan).global_relay_id
        end

        hash
      end

      sig { returns(T::Hash[Integer, T::Boolean]) }
      memoize def extension_access_by_org_id
        org_ids = organizations.map(&:id)
        configs = Copilot::Configuration.where(configurable_type: "Organization", configurable_id: org_ids)

        configs.each_with_object({}) do |config, hash|
          hash[config.configurable_id] = config.copilot_extensions_enabled?
        end
      end
    end
  end
end
