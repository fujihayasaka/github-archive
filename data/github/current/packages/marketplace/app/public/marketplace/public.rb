# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Marketplace
  module Public
    extend T::Helpers
    extend T::Sig
    # Public: Update a listing with the given input attributes.
    #
    # The listing specified will include any errors preventing
    # update from happening after this message called.
    #
    # Returns true if the listing was updated, false otherwise.
    def self.update_listing(listing, inputs:, viewer:)
      inputs = inputs.to_h.with_indifferent_access
      viewer_can_edit = listing.allowed_to_edit?(viewer)
      viewer_is_admin = viewer&.can_admin_marketplace_listings?

      unless viewer_can_edit || viewer_is_admin
        listing.errors.add(:base, "#{viewer} does not have permission to update the listing.")
        return false
      end

      attrs = {}

      primary_category = if inputs[:primary_category_name].present?
        category = Marketplace::Category.find_by(name: inputs[:primary_category_name])
        unless category
          listing.errors.add(:primary_category_id, "No such Marketplace category exists")
          return false
        end
        category
      end

      secondary_category = if inputs[:secondary_category_name] == "none"
        "none"
      elsif inputs[:secondary_category_name].present?
        category = Marketplace::Category.find_by(name: inputs[:secondary_category_name])
        unless category
          listing.errors.add(:secondary_category_id, "No such Marketplace category exists")
          return false
        end
        category
      end

      # Integrators can update text fields, URLs, supported languages, and categories
      if viewer_can_edit
        model_and_input_attributes = {
          bgcolor: :logo_background_color,
          short_description: :short_description,
          name: :name,
          full_description: :full_description,
          extended_description: :extended_description,
          privacy_policy_url: :privacy_policy_url,
          tos_url: :terms_of_service_url,
          company_url: :company_url,
          status_url: :status_url,
          support_url: :support_url,
          technical_email: :technical_email,
          marketing_email: :marketing_email,
          finance_email: :finance_email,
          security_email: :security_email,
          documentation_url: :documentation_url,
          pricing_url: :pricing_url,
          installation_url: :installation_url,
          how_it_works: :how_it_works,
          hero_card_background_image_id: :hero_card_background_image_database_id,
          removal_date: :removal_date,
        }

        model_and_input_attributes.each do |model_attr, input_attr|
          if inputs[input_attr]
            listing.assign_attributes(model_attr => inputs[input_attr].to_s)
          end
        end

        unless inputs[:is_light_text].nil?
          listing.light_text = inputs[:is_light_text]
        end

        supported_language_names = Array(inputs[:supported_language_names])
        if supported_language_names.present?
          listing.languages = LanguageName.lookup_by_names(supported_language_names).compact
        end
      end

      # Bizdevs have ability to change attributes that listing owners do not
      if viewer_is_admin
        listing.skip_draft_validation = true

        if inputs[:oauth_application_database_id]
          attrs[:listable_type] = OauthApplication.name
          attrs[:listable_id] = inputs[:oauth_application_database_id]
        elsif inputs[:app_id]
          attrs[:listable_type] = Integration.name
          attrs[:listable_id] = inputs[:app_id]
        end

        if inputs.key?(:has_direct_billing)
          listing.direct_billing_enabled = inputs[:has_direct_billing]
        end

        if inputs.key?(:is_copilot_app)
          listing.copilot_app = inputs[:is_copilot_app]
        end

        if inputs.key?(:is_by_github)
          listing.by_github = inputs[:is_by_github]
        end

        if inputs.key?(:featured_at)
          listing.featured_at = inputs[:featured_at]
          updated_featured_at = listing.featured_at_changed?
        end
      end

      original_categories = listing.regular_categories.to_a
      original_filters = listing.filter_categories.to_a

      new_categories = []
      if primary_category
        new_categories << primary_category
        listing.primary_category_id = primary_category.id
      else
        new_categories << original_categories.first
      end

      if secondary_category == "none"
        listing.secondary_category_id = nil
      elsif secondary_category
        new_categories << secondary_category
        listing.secondary_category_id = T.unsafe(secondary_category).id
      elsif original_categories.size > 1
        new_categories << original_categories.second
      end

      new_filters = original_filters
      if viewer_is_admin && inputs.key?(:filter_categories)
        filter_categories = inputs[:filter_categories].reject(&:blank?).map do |filter_name|
          Marketplace::Category.find_by(name: filter_name)
        end

        new_filters = filter_categories.compact
      end

      # NOTE: we care about the order of regular categories to make the
      # primary vs secondary distinction. Filters can be in any order.
      categories_updated = (new_categories.map(&:id) != original_categories.map(&:id)) ||
        (new_filters.map(&:id).sort != original_filters.map(&:id).sort)

      listing.categories = new_categories + new_filters if categories_updated
      listing.assign_attributes(attrs)

      saved = listing.save

      if saved
        # Create an audit log event to show a bizdev changed the category on a listing
        if categories_updated && viewer_is_admin
          listing.instrument_category_changed(actor: viewer)
        end

        if updated_featured_at
          listing.instrument_featured_at_changed(actor: viewer)
        end
      end

      saved
    end

    # Public: Create a listing with the given input attributes.
    #
    # When creation fails, the listing returned will include any
    # errors that prevented creation.
    #
    # Returns a marketplace listing that may have creation failures.
    def self.create_listing(inputs:, viewer:)
      inputs = inputs.to_h.with_indifferent_access

      listing = Marketplace::Listing.new

      listable = inputs[:listable]
      unless listable
        listing.errors.add(:base, "An OAuth application or integration is required to create a new Marketplace listing.")
        return listing
      end

      listing.listable = listable

      unless listing.allowed_to_edit?(viewer)
        listing.errors.add(:base, "#{viewer} does not have permission to list the application in the Marketplace.")
        return listing
      end

      listing.name = inputs[:name]
      listing.short_description = inputs[:short_description]
      listing.full_description = inputs[:full_description]
      listing.privacy_policy_url = inputs[:privacy_policy_url].to_s
      listing.support_url = inputs[:support_url].to_s
      listing.installation_url = inputs[:installation_url]
      listing.bgcolor = listable.bgcolor

      category = Marketplace::Category.find_by(name: inputs[:primary_category_name])
      unless category
        listing.errors.add(:primary_category, "No such Marketplace category exists: #{inputs[:primary_category_name]}")
        return listing
      end

      listing.categories = [category]
      listing.primary_category_id = category.id

      if inputs[:supported_language_names].present?
        supported_language_names = inputs[:supported_language_names]

        supported_languages = LanguageName.lookup_by_names(supported_language_names).compact

        if supported_languages.any?
          listing.languages = supported_languages
        end
      end

      if listing.save
        listing.instrument_creation(actor: viewer)
      else
        if listing.errors[:categories].present? && category.errors.full_messages.present?
          listing.errors.delete(:categories)
          category.errors.full_messages.each do |err|
            # NOTE: using primary_category here since that's what the API
            # currently accepts. This should change once we accept multiple
            # categories instead.
            listing.errors.add(:primary_category, err.downcase)
          end
        end
      end

      listing
    end

    # Get Marketplace::Listing's for the given organizations which:
    # - are allowlisted for quick installation during repo creation
    # - have an active subscription on the given account
    # - have an installation for the listing's integration on the given account
    # @return Hash of Hashes Organation#id => Marketplace::Listing => Boolean (whether the listing will auto-install)
    sig { params(organization_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Hash[Marketplace::Listing, T::Boolean]]) }
    def self.quick_installable_for_orgs(organization_ids:)
      auto_installs = Hash.new { |hash, key| hash[key] = [] }
      IntegrationInstallations::Public
        .on_all_repositories_for_targets(organization_ids)
        .pluck(:target_id, :integration_id)
        .each { |organization_id, integration_id| auto_installs[organization_id] << integration_id }

      listings_by_org = Marketplace::Listing
        .subscribed_by(organization_ids)
        .with_installations_on(organization_ids)
        .select("integration_installations.target_id", "marketplace_listings.*")
        .map { |listing| [T.unsafe(listing).target_id, listing] }

      installable_listings_by_org = {}
      listings_by_org.each do |org_id, listing|
        installable_listings_by_org[org_id] ||= {}
        installable_listings_by_org[org_id][listing] = !auto_installs[org_id].include?(listing.listable_id)
      end

      installable_listings_by_org
    end
  end
end
