# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::PublicTest < GitHub::TestCase
  fixtures do
    @bizdev = create(:biztools_user, login: "biztools-user")
  end

  context ".update_listing" do
    test "does not create audit log event when listing owner changes categories" do
      listing = create(:marketplace_listing)
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)

      events = subscribe("marketplace_listing.change_category")

      assert_predicate listing.owner, :user?

      inputs = {
        "slug" => listing.slug,
        "primary_category_name" => category1.name,
        "secondary_category_name" => category2.name,
      }
      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      refute event = events.pop, "an event was created"
    end

    if GitHub.billing_enabled?
      test "creates audit log event when bizdev changes categories" do
        listing = create(:marketplace_listing, :verified)
        category1 = create(:marketplace_category)
        category2 = create(:marketplace_category)

        events = subscribe("marketplace_listing.change_category")

        inputs = {
          "slug" => listing.slug,
          "primary_category_name" => category1.name,
          "secondary_category_name" => category2.name,
        }
        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)

        assert event = events.pop, "no event was created"
        assert_equal "marketplace_listing.change_category", event.name

        expected_payload = {
          marketplace_listing: listing.name,
          marketplace_listing_id: listing.id,
          actor: @bizdev.login,
          actor_id: @bizdev.id,
          user: listing.owner.login,
          user_id: listing.owner.id,
          state: :verified,
          primary_category: category1.name,
          secondary_category: category2.name,
          oauth_application: listing.listable.name,
          oauth_application_id: listing.listable_id,
        }
        assert_equal expected_payload, event.payload
      end

      test "biztools users can change the listing's featured_at date" do
        listing = create(:marketplace_listing, :verified, :with_hero_card)

        feature_time = Time.zone.now

        inputs = {
          "slug" => listing.slug,
          "featured_at" => feature_time,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert_equal feature_time.to_i, listing.reload.featured_at.to_i
      end

      test "creates audit log event when changing featured_at" do
        listing = create(:marketplace_listing, :verified, :with_hero_card)

        events = subscribe("marketplace_listing.change_featured_at")

        feature_time = Time.zone.now

        inputs = {
          "slug" => listing.slug,
          "featured_at" => feature_time,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert event = events.pop, "no event was created"
        assert_equal "marketplace_listing.change_featured_at", event.name

        expected_payload = {
          marketplace_listing: listing.name,
          marketplace_listing_id: listing.id,
          actor: @bizdev.login,
          actor_id: @bizdev.id,
          user: listing.owner.login,
          user_id: listing.owner.id,
          state: :verified,
          primary_category: listing.categories.first.name,
          secondary_category: nil,
          featured_at: feature_time,
          oauth_application: listing.listable.name,
          oauth_application_id: listing.listable_id,
        }
      end

      test "listing owner (non-biztools) cannot change the listing's featured_at date" do
        listing = create(:marketplace_listing, :verified, :with_hero_card)

        inputs = {
          "slug" => listing.slug,
          "featured_at" => Time.zone.now.iso8601,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)
        assert_nil listing.reload.featured_at
      end

      test "biztools user can change the listing's integration" do
        integration1 = create(:integration)
        integration2 = create(:integration)

        listing = create(:marketplace_listing, :verified, listable: integration1)

        inputs = {
          "slug" => listing.slug,
          "app_id" => integration2.id,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert_equal integration2, listing.reload.listable
      end

      test "biztools user can update direct billing permission" do
        listing = create(:marketplace_listing, :verified)

        refute listing.direct_billing_enabled

        inputs = {
          "slug" => listing.slug,
          "has_direct_billing" => true,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert listing.reload.direct_billing_enabled
      end

      test "biztools user can change the listing's integration to an OAuth application" do
        integration = create(:integration)
        app = create :oauth_application

        listing = create(:marketplace_listing, :verified, listable: integration)

        inputs = {
          "slug" => listing.slug,
          "oauth_application_database_id" => app.id,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert_equal app, listing.reload.listable
      end

      test "biztools user can change the listing's OAuth application" do
        app1 = create :oauth_application
        app2 = create :oauth_application

        listing = create(:marketplace_listing, :verified, listable: app1)

        inputs = {
          "slug" => listing.slug,
          "oauth_application_database_id" => app2.id,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert_equal app2, listing.reload.listable
      end

      test "biztools user can change the listing's OAuth application to an integration" do
        app = create :oauth_application
        integration = create(:integration)

        listing = create(:marketplace_listing, :verified, listable: app)

        inputs = {
          "slug" => listing.slug,
          "app_id" => integration.id,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert_equal integration, listing.reload.listable
      end

      test "biztools user can change the listing's filter-type categories" do
        cat1 = create(:marketplace_category, acts_as_filter: true)
        cat2 = create(:marketplace_category, acts_as_filter: true)
        cat3 = create(:marketplace_category)
        filter_cats = [cat1.name, cat2.name]
        all_categories = [cat3.name, cat1.name, cat2.name]

        listing = create(:marketplace_listing, :verified, categories: [cat3])

        inputs = {
          slug: listing.slug,
          filter_categories: filter_cats,
        }

        assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: @bizdev)
        assert_equal all_categories, listing.reload.categories.map { |cat| cat["name"] }
      end
    end

    # https://github.com/github/github/issues/72686
    test "setting background color does not wipe secondary category" do
      cat1 = create(:marketplace_category)
      cat2 = create(:marketplace_category)
      listing = create(
        :marketplace_listing,
        primary_category_id:   cat1.id,
        secondary_category_id: cat2.id,
        categories:            [cat1, cat2],
        bgcolor:               "FAFAFA",
      )

      inputs = {
        "slug" => listing.slug,
        "logo_background_color" => "e0e0e0",
      }

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)
      assert_equal inputs["logo_background_color"], listing.reload.bgcolor
      refute_nil listing.categories.last, "listing should still have a secondary category"
      assert_equal cat2.name, listing.categories.last.name
    end

    test "cannot update categories when listing is not in draft state" do
      integration = create(:integration)
      listing = create(:marketplace_listing, :verified, listable: integration)
      refute_predicate listing, :draft?

      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)
      viewer = integration.owner.admin

      inputs = {
        "slug" => listing.slug,
        "primary_category_name" => category1.name,
        "secondary_category_name" => category2.name,
      }
      assert_equal false, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: viewer)
      assert_equal "Categories cannot be changed since the listing is not a draft", listing.errors.full_messages.to_sentence
    end

    test "listing owner cannot update direct billing permission" do
      listing = create(:marketplace_listing, :verified)

      refute listing.direct_billing_enabled

      inputs = {
        "slug" => listing.slug,
        "has_direct_billing" => true,
      }

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)
      refute listing.reload.direct_billing_enabled
    end

    test "listing owner cannot swap integratable" do
      app = create :oauth_application
      integration = create(:integration)
      viewer = app.user
      listing = create(:marketplace_listing, :verified, listable: app)

      inputs = {
        "slug" => listing.slug,
        "app_id" => integration.id,
      }

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: viewer)
      assert_equal app, listing.reload.listable, "listing app should be the same as before"
    end

    test "can update some fields when listing is no longer a draft" do
      listing = create(:marketplace_listing, :verification_pending_from_draft)
      refute_predicate listing, :draft?

      inputs = {
        "slug" => listing.slug,
        "logo_background_color" => "fefefe",
        "full_description" => "This is clearly an improved description.",
      }

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)
      assert_equal inputs["logo_background_color"], listing.reload.bgcolor
      assert_equal inputs["full_description"], listing.full_description
    end

    test "cannot update any fields when listing is rejected" do
      listing = create(:marketplace_listing, :rejected)

      inputs = {
        "slug" => listing.slug,
        "logo_background_color" => "fefefe",
        "full_description" => "This is clearly an improved description.",
      }

      assert_equal false, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)
      assert_equal "#{listing.owner} does not have permission to update the listing.", listing.errors.full_messages.to_sentence
    end

    test "cannot update any fields when listing is delisted" do
      listing = create(:marketplace_listing, :archived)

      inputs = {
        "slug" => listing.slug,
        "logo_background_color" => "000AAA",
        "extended_description" => "Some might say that this is the best description.",
      }

      assert_equal false, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)
      assert_equal "#{listing.owner} does not have permission to update the listing.", listing.errors.full_messages.to_sentence
    end

    test "integration owner can update draft listing" do
      integration = create(:integration)
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)
      category3 = create(:marketplace_category)
      language = create(:language_name)
      new_supported_language = create(:language_name)
      listing = create(
        :marketplace_listing,
        listable:              integration,
        primary_category_id:   category1.id,
        secondary_category_id: category2.id,
        categories:            [category1, category2],
        languages:             [language],
      )

      inputs = {
        "slug" => listing.slug,
        "primary_category_name" => category3.name,
        "secondary_category_name" => "none",
        "logo_background_color" => "ff00ff",
        "supported_language_names" => new_supported_language.name,
        "security_email" => "security@brandname.pizza",
      }

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: integration.owner.admin)

      assert_equal inputs["logo_background_color"], listing.reload.bgcolor
      assert_equal inputs["security_email"], listing.security_email
      assert_equal 1, listing.categories.count
      assert_equal category3.name, listing.categories.first.name
      assert_equal category3.id, listing.primary_category_id
      assert_nil listing.secondary_category_id
      assert_equal [new_supported_language.name], listing.languages.pluck(:name)
    end

    test "OAuth app owner can update draft listing" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)

      inputs = {
        "slug" => listing.slug,
        "logo_background_color" => "efefef",
      }

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: app.user)
      assert_equal "efefef", listing.reload.bgcolor
    end

    test "user not connected to the listing cannot update draft listing" do
      listing = create(:marketplace_listing, bgcolor: "995C02")
      viewer = create(:user)

      inputs = {
        "slug" => listing.slug,
        "logo_background_color" => "FF00AA",
      }

      assert_equal false, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: viewer)
      assert_equal("#{viewer} does not have permission to update the listing.", listing.errors.full_messages.to_sentence)

      assert_equal "995C02", listing.reload.bgcolor
    end

    test "updating primary_category updates the first category" do
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)

      listing = create(
        :marketplace_listing,
        primary_category_id:  category1.id,
        categories:      [category1],
      )

      inputs = {
        slug: listing.slug,
        primary_category_name: category2.name,
      }

      assert_equal 1, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      assert_equal 1, listing.reload.categories.count
      assert_equal category2.name, listing.categories.first.name
      assert_equal category2.id, listing.primary_category_id
    end

    test "updating secondary_category adds a second category when none exist" do
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)

      listing = create(
        :marketplace_listing,
        primary_category_id:   category1.id,
        categories: [category1],
      )

      inputs = {
        "slug" => listing.slug,
        "secondary_category_name" => category2.name,
      }

      assert_equal 1, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_nil listing.secondary_category_id

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      listing.reload

      assert_equal 2, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_equal category2.name, listing.categories.last.name
      assert_equal category2.id, listing.secondary_category_id
    end

    test "updating secondary_category updates the second category" do
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)
      category3 = create(:marketplace_category)

      listing = create(
        :marketplace_listing,
        primary_category_id: category1.id,
        secondary_category_id: category2.id,
        categories: [category1, category2],
      )

      inputs = {
        slug: listing.slug,
        secondary_category_name: category3.name,
      }

      assert_equal 2, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_equal category2.name, listing.categories.last.name
      assert_equal category2.id, listing.secondary_category_id

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      listing.reload

      assert_equal 2, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_equal category3.name, listing.categories.last.name
      assert_equal category3.id, listing.secondary_category_id
    end

    test "setting secondary_category to none removes the second category" do
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)

      listing = create(
        :marketplace_listing,
        primary_category_id: category1.id,
        secondary_category_id: category2.id,
        categories: [category1, category2],
      )

      inputs = {
        slug: listing.slug,
        secondary_category_name: "none",
      }

      assert_equal 2, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_equal category2.id, listing.secondary_category_id
      assert_equal category2.name, listing.categories.last.name

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      listing.reload

      assert_equal 1, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_nil listing.secondary_category_id
    end

    test "setting secondary_category to none keeps is noop if only one has been set" do
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)

      listing = create(
        :marketplace_listing,
        primary_category_id: category1.id,
        categories: [category1],
      )

      inputs = {
        slug: listing.slug,
        secondary_category_name: "none",
      }

      assert_equal 1, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_nil listing.secondary_category_id

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      listing.reload

      assert_equal 1, listing.categories.count
      assert_equal category1.name, listing.categories.first.name
      assert_equal category1.id, listing.primary_category_id
      assert_nil listing.secondary_category_id
    end

    test "duplicate categories raise an error" do
      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)

      listing = create(
        :marketplace_listing,
        categories:          [category1],
        primary_category_id: category1.id,
      )

      inputs = {
        slug: listing.slug,
        primary_category_name: category2.name,
        secondary_category_name: category2.name,
      }

      assert_equal 1, listing.categories.count
      assert_equal category1.id, listing.categories.first.id
      assert_equal category1.id, listing.primary_category_id
      assert_nil listing.secondary_category_id

      assert_equal false, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      listing.reload

      refute_empty listing.errors.full_messages.to_sentence
      assert_equal 1, listing.categories.count
      assert_equal category1.id, listing.primary_category_id
      assert_nil listing.secondary_category_id
    end

    test "can update security email for approved listing" do
      filter_category = create(:marketplace_category, acts_as_filter: true)
      some_category = create(:marketplace_category)
      other_category = create(:marketplace_category)

      listing = create(:marketplace_listing, :verified, categories: [some_category, filter_category])

      listing.skip_draft_validation = true
      listing.categories = [some_category, other_category] + [filter_category]
      listing.skip_draft_validation = false

      inputs = {
        slug: listing.slug,
        security_email: "foo@bar.com",
        primary_category_name: listing.categories.first.name,
        secondary_category_name: other_category.name,
      }

      assert_nil listing.security_email
      assert_equal 3, listing.categories.count

      assert_equal true, Marketplace::Public.update_listing(listing, inputs: inputs, viewer: listing.owner)

      listing.reload

      assert_equal "foo@bar.com", listing.security_email
      assert_equal 3, listing.categories.count
    end

    test "cannot update without permissions" do
      listing = create(:marketplace_listing, :verified)

      assert_equal false, Marketplace::Public.update_listing(listing, inputs: {}, viewer: nil)
      assert_includes listing.errors.full_messages.to_sentence, "does not have permission to update the listing"

      assert_equal false, Marketplace::Public.update_listing(listing, inputs: {}, viewer: create(:user))
      assert_includes listing.errors.full_messages.to_sentence, "does not have permission to update the listing"
    end
  end

  context ".create_listing" do
    test "pulls bgcolor from backing GitHub App" do
      user = create(:user)
      integration = create(:integration, owner: user, bgcolor: "439C96")
      category = create(:marketplace_category)
      inputs = creation_input(name: "Dark Teal App", category: category, integration: integration)

      listing = Marketplace::Public.create_listing(viewer: user, inputs: inputs)

      assert_predicate listing, :persisted?
      assert_equal integration.bgcolor, listing.bgcolor
    end

    test "pulls bgcolor from backing OAuth App" do
      user = create(:user)
      app = create(:oauth_application, user: user, bgcolor: "6C6C85")
      category = create(:marketplace_category)
      inputs = creation_input(name: "Dark Cobalt App", category: category, oauth_app: app)

      listing = Marketplace::Public.create_listing(viewer: user, inputs: inputs)

      assert_predicate listing, :persisted?
      assert_equal app.bgcolor, listing.bgcolor
    end

    test "sets copilot_app to true if listable has (Copilot Extensions) agent configured" do
      user = create(:user)
      org = create(:organization, admin: user)
      integration = create(:integration, :with_agent, owner: org, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      integration_agent = integration.integration_agent
      integration_agent.update(app_type: "agent")

      inputs = creation_input(name: "Very Cool Agent", category: create(:marketplace_category), integration: integration)

      listing = Marketplace::Public.create_listing(viewer: user, inputs: inputs)

      assert_predicate listing, :persisted?
      assert_predicate listing, :copilot_app?
    end

    test "associates supported languages with listing when supported languages exist" do
      user = create(:user)
      org = create(:organization, admin: user)
      integration = create(:integration, owner: org)
      category = create(:marketplace_category)
      language = create(:language_name)
      inputs = creation_input(name: "Yellow Plastic Cat", category: category,
                              integration: integration, supported_language_names: [language.name])

      listing = Marketplace::Public.create_listing(viewer: user, inputs: inputs)

      assert_predicate listing, :persisted?
      assert_equal [language.name], listing.languages.pluck(:name)
    end

    test "does not associate supported language with listing when language doesn't exist" do
      user = create(:user)
      org = create(:organization, admin: user)
      integration = create(:integration, owner: org)
      category = create(:marketplace_category)
      inputs = creation_input(name: "Yellow Plastic Cat", category: category,
                              integration: integration, supported_language_names: ["Ruby"])

      listing = T.let(nil, T.untyped)
      LanguageName.stub(:lookup_by_names, [nil]) do
        listing = Marketplace::Public.create_listing(viewer: user, inputs: inputs)
      end

      assert_predicate listing, :persisted?
      assert_empty listing.languages.pluck(:name)
    end

    test "associates a new category and persists legacy primary_category" do
      user = create(:user)
      org = create(:organization, admin: user)
      integration = create(:integration, owner: org)
      category = create(:marketplace_category)
      language = create(:language_name)
      inputs = creation_input(name: "Yellow Plastic Cat", category: category,
                              integration: integration, supported_language_names: [language.name])

      listing = Marketplace::Public.create_listing(viewer: user, inputs: inputs)

      assert_predicate listing, :persisted?
      assert_equal 1, listing.categories.count
      assert_equal category.name, listing.categories.first.name
      assert_equal category.id, listing.primary_category_id
    end

    test "creates an audit log event when a listing is created" do
      user = create(:user)
      org = create(:organization, admin: user)
      integration = create(:integration, owner: org)
      category = create(:marketplace_category)
      inputs = creation_input(name: "Yellow Plastic Cat", category: category, integration: integration)

      events = subscribe("marketplace_listing.create")
      listing = T.let(nil, T.untyped)
      assert_difference "Marketplace::Listing.count" do
        listing = Marketplace::Public.create_listing(viewer: user, inputs: inputs)
      end

      assert_predicate listing, :persisted?
      assert event = events.pop, "no event was created"
      assert_equal "marketplace_listing.create", event.name

      expected_payload = {
        marketplace_listing: "Yellow Plastic Cat",
        marketplace_listing_id: T.must(Marketplace::Listing.last).id,
        actor: user.login,
        actor_id: user.id,
        org: org.login,
        org_id: org.id,
        state: :draft,
        primary_category: category.name,
        secondary_category: "none",
        integration_id: integration.id,
        integration: integration.name,
      }
      assert_equal expected_payload, event.payload
    end
  end

  context ".quick_installable_for_orgs" do
    test "returns installed/subscribed github apps for orgs" do
      orgs = create_list(:organization, 2)
      listings = create_installable_listing_for_orgs(orgs: orgs)

      quick_installable = Marketplace::Public.quick_installable_for_orgs(organization_ids: orgs.map(&:id))

      orgs.each do |org|
        quick_installable_for_org = T.must(quick_installable[org.id])
        assert_same_elements quick_installable_for_org.keys, listings[org.id]
        assert quick_installable_for_org.values.all?
      end
    end
  end

  def create_installable_listing(org:)
    listing = create(:marketplace_listing, :integration, state: :verified)
    listing_plan = create(:marketplace_listing_plan, :free, listing: listing)
    user_plan_subscription = create(:billing_plan_subscription, user: org)
    create(:billing_subscription_item,
      plan_subscription: user_plan_subscription,
      subscribable: listing_plan,
      quantity: 1,
    )
    repo = create(:repository, owner: org)
    listing.listable.install_on(org, repositories: [repo], installer: org.owner, entry_point: :test_case)
    listing
  end

  def create_installable_listing_for_orgs(orgs:)
    listings = Hash.new { |hash, key| hash[key] = [] }
    orgs.each do |org|
      listings[org.id] << create_installable_listing(org:)
      make_integration_installation(target: org, permissions: { "metadata" => :read })
    end
    listings
  end

  def creation_input(name:, category:, integration: nil, oauth_app: nil, supported_language_names: [])
    input = {
      "name" => name,
      "short_description" => "It sits on your desk and contemplates life",
      "full_description" => "Longingly, it stares at the can of plastic tuna.",
      "primary_category_name" => category.name,
      "privacy_policy_url" => "https://example.com/privacy",
      "support_url" => "https://example.com/support",
      "installation_url" => "https://yellow.example.com/plastic-cat/install",
      "supported_language_names" => supported_language_names,
    }
    input["listable"] = integration if integration
    input["listable"] = oauth_app if oauth_app
    input
  end
end
