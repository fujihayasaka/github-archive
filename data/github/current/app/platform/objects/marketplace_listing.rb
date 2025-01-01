# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceListing < Platform::Objects::Base
      model_name "Marketplace::Listing"
      description "A listing in the GitHub integration marketplace."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, marketplace_listing)
        # Determine whether the target requesting access should be allowed to hit Marketplace GQL endpoints.
        # Currently, only "Custom-OG-Image" GH App is permitted to access these endpoints which is checked by the below feature flag
        # If some more GH Apps needs this access, we can add the integration id in /devtools/feature_flags/endpoint_exception_for_customog.
        # We can remove the feature flag, in future if needed, by directly comparing the integration which is in need of access with permission.integration variable
        check_allow_integration = GitHub.flipper[:marketplace_gql_endpoint_exception].enabled?(permission&.integration)

        marketplace_listing.async_target_for_conditional_access.then do |tfca|
          permission.access_allowed?(
            :read_marketplace_listing,
            resource: marketplace_listing,
            marketplace_listing: marketplace_listing,
            current_org: tfca.is_a?(::Organization) ? tfca : nil,
            tfca: tfca,
            current_repo: nil,
            allow_integrations: check_allow_integration,
            allow_user_via_granular_actor: false
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::Listing object
      #
      # See https://github.com/github/marketplace/blob/master/docs/graphql-permissions.md for
      # more context around this implementation.
      def self.async_viewer_can_see?(permission, object)
        if object.publicly_listed?
          true
        elsif permission.authenticating_as_app?
          if object.listable_is_integration?
            object.listable_id == permission.integration.id
          elsif object.listable_is_oauth_application?
            object.listable_id == permission.oauth_app.id
          end
        elsif permission.viewer.nil?
          false
        elsif permission.viewer.user_or_org_account_has_purchased_listing?(object)
          true
        elsif permission.viewer.can_admin_marketplace_listings?
          true
        else
          object.async_owner.then do |owner|
            allowed_ids = owner.user? ? [owner.id] : owner.direct_admin_ids
            allowed_ids.include?(permission.viewer.id)
          end
        end
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["repo"]

      implements_node templates: [
        [:uaml, :user_id, :application_id, :marketplace_listing_id],
        [:oaml, :organization_id, :application_id, :marketplace_listing_id],
        [:uoaml, :user_id, :oauth_application_id, :marketplace_listing_id],
        [:ooaml, :organization_id, :oauth_application_id, :marketplace_listing_id]
      ], as: "ML", ready_date: "2021-07-14" do |marketplace_listing|
        marketplace_listing.async_listable.then do |integratable|
          marketplace_listing.async_owner.then do |owner|
            global_id = {
              marketplace_listing_id: marketplace_listing.id
            }

            if marketplace_listing.listable_is_integration?
              global_id[:application_id] = integratable.id

              if owner&.organization?
                global_id[:prefix] = :oaml
                global_id[:organization_id] = owner.id
              else
                global_id[:prefix] = :uaml
                global_id[:user_id] = owner&.id
              end
            elsif marketplace_listing.listable_is_oauth_application?
              global_id[:oauth_application_id] = integratable.id

              if owner&.organization?
                global_id[:prefix] = :ooaml
                global_id[:organization_id] = owner.id
              else
                global_id[:prefix] = :uoaml
                global_id[:user_id] = owner&.id
              end
            end

            global_id
          end
        end
      end

      database_id_field(visibility: :internal)
      field :name, String, "The listing's full name.", null: false
      field :slug, String, "The short name of the listing used in its URL.", null: false
      field :extended_description, String, "The listing's detailed description.", null: true
      field :how_it_works, String, "A technical description of how this app works with GitHub.", null: true

      field :privacy_policy_url, Scalars::URI, "URL to the listing's privacy policy, may return an empty string for listings that do not require a privacy policy URL.", null: false

      def privacy_support_url
        @object.privacy_support_url || ""
      end

      field :support_url, Scalars::URI, "Either a URL or an email address for support for this listing's app, may return an empty string for listings that do not require a support URL.", null: false

      def support_url
        @object.support_url || ""
      end

      field :support_email, String, "An email address for support for this listing's app.", null: true

      field :company_url, Scalars::URI, "URL to the listing owner's company site.", null: true
      field :documentation_url, Scalars::URI, "URL to the listing's documentation.", null: true

      field :installation_url, Scalars::URI, "URL to install the product to the viewer's account or organization.", null: true
      field :pricing_url, Scalars::URI, "URL to the listing's detailed pricing.", null: true
      field :status_url, Scalars::URI, "URL to the listing's status page.", null: true
      field :terms_of_service_url, Scalars::URI, "URL to the listing's terms of service.", method: :tos_url, null: true

      field :technical_email, String, "Email address for the listing's technical contact.", null: true, visibility: :internal
      field :marketing_email, String, "Email address for the listing's marketing contact.", null: true, visibility: :internal
      field :finance_email, String, "Email address for the listing's finance contact.", null: true, visibility: :internal
      field :security_email, String, "Email address for the listing's security contact.", null: true, visibility: :internal

      field :featured_at, Scalars::DateTime, "Identifies the date and time when the listing is featured on the Marketplace homepage.", visibility: :internal, null: true
      field :is_featured, Boolean, "Whether the listing is featured on the Marketplace homepage.", method: :featured?, visibility: :internal, null: false
      field :is_featurable, Boolean, "Whether the listing can be featured on the homepage.", method: :featurable?, visibility: :internal, null: false
      field :logo_background_color, String, "The hex color code, without the leading '#', for the logo background.", method: :bgcolor, null: false
      field :is_light_text, Boolean, "Whether light text is used when the logo is displayed.", method: :light_text, visibility: :internal, null: false
      field :is_paid, Boolean, "Whether the product this listing represents is available as part of a paid plan.", method: :paid?, null: false
      field :default_plan, Objects::MarketplaceListingPlan, "The default plan for this listing.", null: true, visibility: :internal
      field :has_published_free_plans, Boolean, "Whether or not this listing has published any free plans", method: :published_free_plans?, null: false, visibility: :internal
      field :has_published_paid_plans, Boolean, "Whether or not this listing has published any paid plans", method: :published_paid_plans?, null: false, visibility: :internal
      field :remaining_plan_count, Integer, "How many more payment plans can be added to this listing.", visibility: :internal, null: false
      field :remaining_screenshot_count, Integer, "How many more screenshots can be uploaded to this listing.", visibility: :internal, null: false
      field :is_by_github, Boolean, "Whether this listing is owned by GitHub", method: :by_github?, visibility: :internal, null: false
      field :installation_url_requirement_is_met, Boolean, "Whether this listing has an installation URL or doesn't require one", method: :installation_url_requirement_met?, visibility: :internal, null: :false
      field :has_reached_maximum_plan_count, Boolean, "Whether this listing has reached the maximum allowed number of published plans.", method: :reached_maximum_plan_count?, visibility: :internal, null: :false
      field :are_published_paid_plans_allowed, Boolean, "Whether paid plans are permitted given the listing's verification status.", method: :published_paid_plans_allowed?, visibility: :internal, null: :false
      field :can_initiate_financial_onboarding, Boolean, "Financial onboarding initiation requirements are met or not", method: :initiate_financial_onboarding?, visibility: :internal, null: :false

      field :is_draft, Boolean, "Whether this listing is still an editable draft that has not been submitted for review and is not publicly visible in the Marketplace.", null: false, method: :draft?
      field :is_verification_pending_from_draft, Boolean, "Whether this draft listing has been submitted for review from GitHub for approval to be verified in the Marketplace.", null: false, method: :verification_pending_from_draft?
      field :is_verification_pending_from_unverified, Boolean, "Whether this unverified listing has been submitted for review from GitHub for approval to be verified in the Marketplace.", null: false, method: :verification_pending_from_unverified?
      field :is_unverified_pending, Boolean, "Whether this draft listing has been submitted for review for approval to be unverified in the Marketplace.", null: false, method: :unverified_pending?
      field :is_verified, Boolean, "Whether this listing has been approved for verified display in the Marketplace.", method: :verified?, null: false
      field :is_unverified, Boolean, "Whether this listing has been approved for unverified display in the Marketplace.", method: :unverified?, null: false
      field :is_rejected, Boolean, "Whether this listing has been rejected by GitHub for display in the Marketplace.", method: :rejected?, null: false
      field :is_verified_creator, Boolean, "Whether the creator of the app is verified or not", method: :verified_creator?, visibility: :internal, null: false
      field :has_verified_owner, Boolean, "Whether the creator of the app is a verified org", method: :verified_owner?, null: false
      field :is_owner_verification_pending, Boolean, "Whether the publisher verification is pending", method: :owner_verification_pending?, visibility: :internal, null: false
      field :has_installation_requirements_met, Boolean, "Whether installation requirements met for publishing the paid plan", method: :has_installation_requirements_met?, visibility: :internal, null: false
      field :is_verified_listing, Boolean, "Whether listing is in verified or verified creator state", method: :verified_listing?, visibility: :internal, null: false
      field :is_publish_pending, Boolean, "Whether listing is in pending state of publishing", method: :publish_pending?, visibility: :internal, null: false
      field :show_paid_plan_checks_on_draft_listing, Boolean, "Whether paid plans checks need to be verified to allow submitting draft app for review", method: :show_paid_plan_checks_on_draft_listing?, visibility: :internal, null: false
      field :can_publish_with_paid_plans, Boolean, "Whether draft app with published paid plans can request for app publishing", method: :allow_app_publish?, visibility: :internal, null: false

      field :is_archived, Boolean, "Whether this listing has been removed from the Marketplace.", method: :archived?, null: false
      field :has_direct_billing, Boolean, "Whether this listing can create direct billing plans.", visibility: :internal, method: :direct_billing_enabled?, null: false

      field :is_ready_for_submission, Boolean, "Whether this listing has all the attributes needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :async_ready_for_submission?, null: false
      field :listing_description_is_completed, Boolean, "Whether this listing has all the description attributes needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :listing_description_completed?, null: false
      field :naming_and_links_are_completed, Boolean, "Whether this listing has the naming and links needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :naming_and_links_completed?, null: false
      field :contact_info_is_completed, Boolean, "Whether this listing has the contact info needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :contact_info_completed?, null: false
      field :logo_and_feature_card_are_completed, Boolean, "Whether this listing has the logo and feature card needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :logo_and_feature_card_completed?, null: false
      field :listing_details_are_completed, Boolean, "Whether this listing has the descriptions needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :listing_details_completed?, null: false
      field :plans_and_pricing_are_completed, Boolean, "Whether this listing has the plans needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :plans_and_pricing_completed?, null: false
      field :product_screenshots_are_completed, Boolean, "Whether this listing has the screenshots needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :product_screenshots_completed?, null: false
      field :webhook_is_completed, Boolean, "Whether this listing has the webhook needed for the integrator to request it be published to the Marketplace.", visibility: :internal, method: :async_webhook_completed?, null: false
      field :is_recommended, Boolean, "Whether this listing is recommended or not", visibility: :internal, method: :async_is_recommended?, null: false
      field :oauth_application_database_id, Integer, "The primary key of the listing's OAuth application", visibility: :internal, null: true

      def oauth_application_database_id
        @object.listable_id if @object.listable_is_oauth_application?
      end

      field :integratable_is_integration, Boolean, "Whether this listing's app is an Integration", visibility: :internal, method: :listable_is_integration?, null: false
      field :integratable_is_oauth_application, Boolean, "Whether this listing's app is an OauthApplication", visibility: :internal, method: :listable_is_oauth_application?, null: false
      # TODO should use `Id`, not `ID`, like `databaseId`
      field :heroCardBackgroundImageDatabaseID, Integer, "The primary key of the listing's hero card background image.", visibility: :internal, method: :hero_card_background_image_id, null: true

      url_fields description: "The HTTP URL for the Marketplace listing." do |listing|
        template = Addressable::Template.new("/marketplace/{slug}")
        template.expand slug: listing.slug
      end

      field :short_description, String, "The listing's very short description.", null: false

      def short_description
        @object.short_description || ""
      end

      field :can_move_to_verified_creator, Boolean, "Whether listing can move to verified creator or not.", null: false, visibility: :internal

      def can_move_to_verified_creator
        @object.verification_pending_from_draft? || @object.verification_pending_from_unverified? || @object.archived?
      end

      field :can_move_to_verified, Boolean, "Whether listing can move to verified or not.", null: false, visibility: :internal

      def can_move_to_verified
        @object.verified_creator?
      end

      field :normalized_short_description, String, "The listing's very short description without a trailing period or ampersands.", null: false

      def normalized_short_description
        @object.normalized_short_description || ""
      end

      field :full_description, String, "The listing's introductory description.", null: false

      def full_description
        @object.full_description || ""
      end

      field :status, String, "The current status of the Marketplace Listing", null: false, visibility: :internal

      field :previous_state, Enums::MarketplaceListingState, "The previous state of a listing that is awaiting approval.", null: true, visibility: :internal

      def previous_state
        if @object.verification_pending_from_unverified?
          "unverified"
        elsif @object.verification_pending_from_draft? || @object.unverified_pending?
          "draft"
        end
      end

      field :is_pending_approval, Boolean, "Whether this listing has been submitted for review as verified or unverified in the Marketplace.", null: false, visibility: :internal

      def is_pending_approval
        @object.verification_pending_from_draft? || @object.verification_pending_from_unverified? || @object.unverified_pending?
      end

      field :is_public, Boolean, "Whether this listing has been approved for display in the Marketplace.", null: false, method: :publicly_listed?

      field :admin_info, Objects::MarketplaceListingAdminInfo, description: "Listing information only visible to site administrators.", null: true

      def admin_info
        if @context[:viewer] && (@context[:viewer].can_admin_marketplace_listings? || @object.adminable_by?(@context[:viewer]))
          Models::MarketplaceListingAdminInfo.new(@object)
        else
          nil
        end
      end

      field :has_published_free_trial_plans, Boolean, description: "Does this listing have any plans with a free trial?", null: false

      def has_published_free_trial_plans
        @object.listing_plans.with_published_state.where(has_free_trial: true).any?
      end

      field :has_terms_of_service, Boolean, description: "Does this listing have a terms of service link?", null: false

      def has_terms_of_service
        @object.tos_url.present?
      end

      field :viewer_has_purchased_for_all_organizations, Boolean, null: false, description: <<~DESCRIPTION
        Indicates if the current user has purchased a subscription to this Marketplace listing
        for all of the organizations the user owns.
      DESCRIPTION

      def viewer_has_purchased_for_all_organizations
        if @context[:viewer]
          billed_orgs = @context[:viewer].billed_organizations_for_marketplace_listing(@object.id)
          owned_orgs = @context[:viewer].owned_organizations

          billed_org_ids = billed_orgs.map(&:id).sort
          owned_org_ids = owned_orgs.map(&:id).sort

          billed_org_ids == owned_org_ids
        else
          false
        end
      end

      field :viewer_active_plan, Objects::MarketplaceListingPlan, null: true, description: <<~DESCRIPTION
        Returns this listing's plan for which the current user has an active subscription.
      DESCRIPTION

      def viewer_active_plan
        return unless user = @context[:viewer]

        user.async_plan_subscription.then do |_plan_subscription|
          listing_plans_ids = Marketplace::ListingPlan.where(marketplace_listing_id: @object.id).pluck(:id)
          user.active_subscription_items.for_marketplace_listing_plans(listing_plans_ids).first&.async_subscribable
        end
      end

      field :viewer_billed_organizations, Connections.define(Objects::Organization), visibility: :internal, null: true, description: <<~DESCRIPTION
        Returns the organizations for which the current user is an administrator that have a
        subscription to this Marketplace listing.
      DESCRIPTION

      def viewer_billed_organizations
        if @context[:viewer]
          ArrayWrapper.new(@context[:viewer].billed_organizations_for_marketplace_listing(@object.id))
        else
          ArrayWrapper.new([])
        end
      end

      field :viewer_has_purchased, Boolean, null: false, description: <<~DESCRIPTION
        Indicates whether the current user has an active subscription to this Marketplace listing.
      DESCRIPTION

      def viewer_has_purchased
        if @context[:viewer]
          @context[:viewer].async_has_purchased_marketplace_listing?(@object.id)
        else
          false
        end
      end

      field :viewer_organization_subscription_items, Connections::SubscriptionItem, null: true, description: <<~DESCRIPTION
        Subscription items for this listing for organizations of which the current user
        is an administrator.
      DESCRIPTION

      def viewer_organization_subscription_items
        if @context[:viewer]
          items = @context[:viewer].owned_organizations.map do |org|
            item = org.subscription_item_for_marketplace_listing(@object.id)
            item if item && item.adminable_by?(@context[:viewer])
          end
          ArrayWrapper.new(items.compact)
        else
          ArrayWrapper.new([])
        end
      end

      field :viewer_has_signed_latest_integrator_agreement, Boolean, visibility: :internal, null: false, description: <<~DESCRIPTION
        Has the the latest version of the GitHub Marketplace Developer Agreement been signed
        by the necessary user or organization for this listing.
      DESCRIPTION

      def viewer_has_signed_latest_integrator_agreement
        agreement = Marketplace::Agreement.latest_for_integrators
        @object.has_signed_integrator_agreement?(agreement: agreement, actor: @context[:viewer])
      end

      field :viewer_has_signed_latest_end_user_agreement, Boolean, visibility: :internal, null: false, description: <<~DESCRIPTION
        Has the current viewer signed the latest version of the GitHub Marketplace Terms of
        Service.
      DESCRIPTION

      def viewer_has_signed_latest_end_user_agreement
        agreement = Marketplace::Agreement.latest_for_end_users
        @object.has_signed_end_user_agreement?(agreement: agreement, actor: @context[:viewer])
      end

      field :viewer_can_sign_end_user_agreement, Boolean, visibility: :internal, null: false, description: "Can the current viewer sign the GitHub Marketplace Terms of Service for\ninstalling/purchasing this listing's app." do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :agreementID, ID, "The ID of a particular end-user agreement.", required: false,
          as: :agreement_id
      end

      def viewer_can_sign_end_user_agreement(**arguments)
        agreement = if arguments[:agreement_id]
          Helpers::NodeIdentification.typed_object_from_id([Objects::MarketplaceAgreement],
                                                           arguments[:agreement_id], @context)
        else
          Marketplace::Agreement.latest_for_end_users
        end

        @object.can_sign_end_user_agreement?(@context[:viewer], agreement: agreement)
      end

      field :viewer_can_sign_integrator_agreement, Boolean,
        "Can the current viewer sign the GitHub Marketplace Developer Agreement for publishing\nthis listing in the GitHub Marketplace.",
        visibility: :internal, null: false do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :agreementID, ID, "The ID of a particular integrator agreement.", required: false,
          as: :agreement_id
      end

      def viewer_can_sign_integrator_agreement(**arguments)
        agreement = if arguments[:agreement_id]
          Helpers::NodeIdentification.typed_object_from_id([Objects::MarketplaceAgreement],
                                                           arguments[:agreement_id], @context)
        else
          Marketplace::Agreement.latest_for_integrators
        end

        @object.can_sign_integrator_agreement?(@context[:viewer], agreement: agreement)
      end

      field :viewer_can_read_insights, Boolean, description: "Can the current viewer read this Marketplace listings insights.", null: false, visibility: :internal

      def viewer_can_read_insights
        return false if @context[:viewer].blank?

        @object.async_can_viewer_read_insights?(@context[:viewer])
      end

      field :viewer_can_edit, Boolean, description: "Can the current viewer edit this Marketplace listing.", null: false

      def viewer_can_edit
        return false if @context[:viewer].blank?

        @object.async_owner.then do
          @object.allowed_to_edit?(@context[:viewer])
        end
      end

      field :viewer_can_add_plans, Boolean, description: "Can the current viewer add plans for this Marketplace listing.", null: false

      def viewer_can_add_plans
        @object.allowed_to_add_plans?(@context[:viewer])
      end

      field :viewer_can_edit_plans, Boolean, description: "Can the current viewer edit the plans for this Marketplace listing.", null: false

      def viewer_can_edit_plans
        @object.allowed_to_edit?(@context[:viewer])
      end

      field :viewer_can_edit_categories, Boolean, description: <<~DESCRIPTION, null: false do
          Can the current viewer edit the primary and secondary category of this
          Marketplace listing.
        DESCRIPTION
      end

      def viewer_can_edit_categories
        @object.allowed_to_edit_categories?(@context[:viewer])
      end

      field :viewer_can_redraft, Boolean, null: false, description: <<~DESCRIPTION
        Can the current viewer return this Marketplace listing to draft state
        so it becomes editable again.
      DESCRIPTION

      def viewer_can_redraft
        return false if @context[:viewer].blank?
        return false unless @object.can_redraft?

        @object.adminable_by?(@context[:viewer])
      end

      field :viewer_can_request_approval, Boolean, null: false, description: <<~DESCRIPTION
        Can the current viewer request this listing be reviewed for display in
        the Marketplace as verified.
      DESCRIPTION

      def viewer_can_request_approval
        @object.async_can_request_approval?(@context[:viewer])
      end

      field :viewer_can_request_unverified_approval, Boolean, null: false, visibility: :under_development, description: <<~DESCRIPTION
        Can the current viewer request this listing be reviewed for display in
        the Marketplace as unverified.
      DESCRIPTION

      def viewer_can_request_unverified_approval
        @object.async_unverified_approval_requestable_by?(@context[:viewer])
      end

      field :viewer_can_approve, Boolean, description: "Can the current viewer approve this Marketplace listing.", null: false

      def viewer_can_approve
        return false if @context[:viewer].blank?
        return false unless @object.can_approve?

        @context[:viewer].can_admin_marketplace_listings?
      end

      field :viewer_can_delist, Boolean, description: "Can the current viewer delist this Marketplace listing.", null: false

      def viewer_can_delist
        return false if @context[:viewer].blank?
        return false unless @object.can_delist?

        @context[:viewer].can_admin_marketplace_listings?
      end

      field :viewer_can_reject, Boolean, null: false, description: <<~DESCRIPTION
        Can the current viewer reject this Marketplace listing by returning it to
        an editable draft state or rejecting it entirely.
      DESCRIPTION

      def viewer_can_reject
        return false if @context[:viewer].blank?
        return false unless @object.can_reject? || @object.can_redraft?

        @context[:viewer].can_admin_marketplace_listings?
      end

      field :viewer_is_listing_admin, Boolean, null: false, description: <<~DESCRIPTION
        Does the current viewer role allow them to administer this Marketplace listing.
      DESCRIPTION

      def viewer_is_listing_admin
        return false if @context[:viewer].blank?

        @object.adminable_by?(@context[:viewer])
      end

      field :owner, Interfaces::MarketplaceListingOwner, description: "The User or Organization owner of the OAuth application or integration behind this Marketplace listing.", null: true

      def owner
        @object.async_owner.then do |owner|
          owner unless owner&.hide_from_user?(@context[:viewer])
        end
      end

      field :primary_category, MarketplaceCategory, description: "The category that best describes the listing.", null: false

      def primary_category
        @object.categories.where(acts_as_filter: false).first
      end

      field :secondary_category, MarketplaceCategory, description: "An alternate category that describes the listing.", null: true

      def secondary_category
        @object.categories.where(acts_as_filter: false).second
      end

      field :categories, [MarketplaceCategory], "A collection of categories that describe this listing.", null: false, visibility: :under_development

      def categories
        Loaders::MarketplaceListingCategories.load(@object.id)
      end

      field :languages, Connections::RepositoryLanguage, visibility: :internal, description: "A list of software languages supported by this listing.", null: true, connection: true

      def languages
        supported_languages = @object.supported_languages
        language_name_ids = supported_languages.pluck(:language_name_id)
        return supported_languages if language_name_ids.length <= 0

        ordered_language_names_ids = ::LanguageName.where(id: language_name_ids).order("name").pluck(:id)

        supported_languages.
          where(language_name_id: ordered_language_names_ids).
          order(Arel.sql("FIELD(language_name_id, #{ordered_language_names_ids.join(', ')})")).
          order(:id)
      end

      field :plans, Connections::MarketplaceListingPlan, description: "A list of the payment plans for this Marketplace listing.", null: true, numeric_pagination_enabled: true do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :published, Boolean, "Filter out retired plans.", required: false
        argument :retired, Boolean, "Filter out published plans.", required: false, visibility: :internal
      end

      def plans(**arguments)
        plans = @object.listing_plans
        if arguments[:published]
          plans = plans.with_published_state
        elsif arguments[:retired]
          plans = plans.with_retired_state
        end

        plans.scoped.order("marketplace_listing_plans.yearly_price_in_cents")
      end

      field :subscription_items, Connections::SubscriptionItem, visibility: :internal, description: "A list of the subscription items associated with this listing.", null: false do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :not_installed_only, Boolean, "Return only subscription items that haven't installed this listing's app.", required: false, default_value: false
      end

      def subscription_items(**arguments)
        return ArrayWrapper.new([]) unless @object.owner_or_admin?(@context[:viewer])

        if arguments[:not_installed_only]
          @object.subscription_items.active.not_installed
        else
          @object.subscription_items.active
        end
      end

      field :screenshots, Connections.define(Objects::MarketplaceListingScreenshot), description: "A list of the screenshots for this Marketplace listing.", null: true, connection: true

      def screenshots
        @object.screenshots.order(:sequence)
      end

      field :featured_organizations, [MarketplaceListingFeaturedOrganization], description: "A list of the featured organizations for this Marketplace listing.",
        visibility: :internal, null: true do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :approved_only, Boolean, "Returns approved featured organizations only.", required: false, default_value: true, visibility: :internal
      end

      def featured_organizations(**arguments)
        unless @object.allowed_to_edit?(@context[:viewer])
          arguments[:approved_only] = true
        end

        relation = @object.featured_organizations_non_spammy

        relation = relation.approved if arguments[:approved_only]

        Platform::Loaders::ActiveRecord.load_relation(relation).then do |featured_orgs|
          ArrayWrapper.new(featured_orgs)
        end
      end

      field :insights, Connections.define(Objects::MarketplaceListingInsight), description: "Sales metrics for this Marketplace listing over a specified time period.", null: true, connection: true do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :period, Enums::MarketplaceListingInsightPeriod, "The time period to include.", required: true
        argument :end_date, Scalars::Date, "Return metrics up until this date. Defaults to most recent day we have all metrics available for (two days behind the current date).", required: false

        # DAY, WEEK, and MONTH periods return individual rows from marketplace_listing_insights,
        # which paginate beautifully with our GraphQL cursor-based system. The ALLTIME period
        # does not, because it aggregates rows by month and returns things that look like
        # individual insight rows but aren't, and notably the scope doesn't work correctly with
        # the pluck(:id) that pagination wants to do. So we use ArrayWrapper to keep everyone
        # happy.
        #
        # WRT pagination concerns, the DAY, WEEK, and MONTH periods limit results to fit well
        # under the maximum page size; and ALLTIME will allow for 8.3 years worth of insight
        # results before crossing this page size boundary.
        #
        # Note: we should try to fix this association load before making it public; the ALLTIME
        # use case summing across records makes this tricky for platform loaders.
      end

      def insights(**arguments)
        unless @object.owner_or_admin?(@context[:viewer])
          return ArrayWrapper.new([])
        end

        if arguments[:end_date]
          ArrayWrapper.new(@object.insights.for_period(arguments[:period], arguments[:end_date]).to_a)
        else
          ArrayWrapper.new(@object.insights.for_period(arguments[:period]).to_a)
        end
      end

      field :integrator_agreement_signature, Objects::MarketplaceAgreementSignature, description: "The viewer's signed agreement as an integrator, for this listing.", null: true

      def integrator_agreement_signature
        if @context[:viewer]
          @object.integrator_agreement_signature_for(@context[:viewer])
        else
          nil
        end
      end

      field :full_description_html, Scalars::HTML, description: "The listing's introductory description rendered to HTML.", null: false

      def full_description_html
        Platform::Helpers::MarketplaceListingContent.html_for(
          @object, :full_description, { current_user: @context[:viewer] }
        )
      end

      field :extended_description_html, Scalars::HTML, description: "The listing's detailed description rendered to HTML.", null: false

      def extended_description_html
        Platform::Helpers::MarketplaceListingContent.html_for(
          @object, :extended_description, { current_user: @context[:viewer] }
        )
      end

      field :how_it_works_html, Scalars::HTML, description: "The listing's technical description rendered to HTML.", null: false

      def how_it_works_html
        Platform::Helpers::MarketplaceListingContent.html_for(
          @object, :how_it_works, { current_user: @context[:viewer] }
        )
      end

      field :app, App, description: "The GitHub App this listing represents.", null: true

      def app
        if @object.listable_is_integration?
          Loaders::ActiveRecord.load(::Integration, @object.listable_id)
        end
      end

      field :integration_type, Enums::IntegrationType, description: "The type of integration this listing represents", null: false

      def integration_type
        if @object.listable_is_integration?
          "github_app"
        elsif @object.listable_is_oauth_application?
          "oauth"
        else
          "none"
        end
      end

      field :installation_count, Integer, visibility: :internal, description: "The number of times this integration has been installed since :since", null: false do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :since, Scalars::DateTime, "Only count installations created after this ISO8601 time", required: false
      end

      def installation_count(**arguments)
        @object.async_cached_installation_count(since: arguments[:since])
      end

      field :required_installations_for_verification, Integer, visibility: :internal, description: "Number of required installations to be able to request verification", null: false

      field :logo_url, Scalars::URI, description: "URL for the listing's logo image.", null: true do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :size, Integer, "The size in pixels of the resulting square image.", default_value: 400, required: false
      end

      def logo_url(**arguments)
        @object.primary_avatar_url(arguments[:size])
      end

      field :hero_card_background_url, Scalars::URI, visibility: :internal, description: "URL for the listing's hero card background image.", null: true

      def hero_card_background_url
        return unless @object.hero_card_background_image_id

        Loaders::ActiveRecord.load(::Marketplace::ListingImage, @object.hero_card_background_image_id).then do |image|
          if image
            image.hero_image_url(@context[:viewer])
          end
        end
      end

      field :installed_for_viewer, Boolean, description: "Whether this listing's app has been installed for the current viewer", null: false

      def installed_for_viewer
        if @context[:viewer]
          # FIXME: this needs to use a loader
          @object.installed_for?(@context[:viewer])
        else
          false
        end
      end

      url_fields prefix: "configuration", description: "The HTTP URL for configuring access to the listing's integration or OAuth app" do |listing|
        listing.configuration_path
      end

      field :screenshot_urls, [String, null: true], description: "The URLs for the listing's screenshots.", null: false

      def screenshot_urls
        scope = @object.screenshots.order(:sequence)
        ::Promise.all(scope.map do |screenshot|
          screenshot.async_listing.then do
            screenshot.storage_external_url(@context[:viewer])
          end
        end)
      end

      field :show_social_proof, Boolean, "Whether to show recommended label or app install count on search restults", visibility: :internal, null: false

      def show_social_proof
        @object.show_recommended_or_install_count
      end

      field :og_image_url, Scalars::URI,
        description: "The image URL used to represent this resource in open graph data",
        visibility: :internal,
        method: :og_image_url,
        null: true

    end
  end
end
