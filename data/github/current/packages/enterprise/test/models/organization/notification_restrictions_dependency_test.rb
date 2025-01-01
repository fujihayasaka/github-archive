# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::NotificationRestrictionsDependencyTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @org = create(:business_plus_org)
    @org_admin = @org.admin
    @repo = create(:repository, owner: @org)
    @domain = create(:verifiable_domain, domain: "sombra.example.com", owner: @org, verified: true)
    @other_domain = create(:verifiable_domain, owner: @org, verified: true)
    @unverified_domain = create(:verifiable_domain, owner: @org)
    @org.terms_of_service.update(type: "Corporate", actor: @org_admin)
    @member = create(:user)
    @other_member = create(:user)
    @org.add_member(@member)
    @org.add_member(@other_member)

    @business_owner = create(:user)
    @business = create :business, owners: [@business_owner]
    @business_domain = create(:verifiable_domain, owner: @business, verified: true)
    @business_owned_org = create(:business_plus_org, admin: @business_owner, business: @business)

    @restricted_org = create(:business_plus_organization, admin: @org_admin)
    @domain = create(:verifiable_domain, domain: "sombra.example.com",
                     owner: @restricted_org, verified: true)
    @mixed_case_domain = create \
      :verifiable_domain,
      domain: "SOMETHINGELSE.com",
      owner: @restricted_org,
      verified: true
    @collab = create(:user)
    @repo = create(:repository, owner: @restricted_org)
    @restricted_org.add_member(@member)
    @repo.add_member(@collab)
  end

  setup do
    @restricted_org.enable_notification_restrictions(actor: @org_admin)
  end

  context "#members_without_eligible_email" do
    if GitHub.email_verification_enabled?
      test "with email verification enabled returns members who do not have a verified email that matches a verified domain" do
        @org_admin.add_email("alice@sombra.example.com").verify!
        @member.add_email("bob@sombra.example.com")

        assert_same_elements [@member, @other_member], @org.members_without_eligible_email
      end
    else
      test "with email verification disabled returns members who do not have any email that matches a verified domain" do
        @org_admin.add_email("alice@sombra.example.com")
        @member.add_email("bob@sombra.example.com")

        assert_same_elements [@other_member], @org.members_without_eligible_email
      end
    end

    test "does not return any users when there are no verified domains in the org" do
      org = create(:business_plus_organization)
      domain = create(:verifiable_domain, owner: org)

      @org_admin.add_email("alice@sombra.example.com").verify!
      @member.add_email("bob@sombra.example.com")

      assert_equal 0, org.verifiable_domains.verified.count
      assert_empty org.members_without_eligible_email
    end
  end

  context "#notifiable_emails_for" do
    test "returns emails from verified domain if restrictions are enabled" do
      assert @org.enable_notification_restrictions(actor: @org_admin)
      @org_admin.add_email("sombra@#{@unverified_domain.domain}").verify!
      email = @org_admin.add_email("sombra@#{@domain.domain}")
      other_email = @org_admin.add_email("sombra@#{@other_domain.domain}")
      email.verify!
      other_email.verify!

      assert_same_elements [email, other_email], @org.notifiable_emails_for(@org_admin)
    end

    test "returns notifiable emails for member if restrictions are not enabled" do
      email = @org_admin.add_email("sombra@#{@domain.domain}")
      other_email = @org_admin.add_email("sombra@#{@other_domain.domain}")
      email.verify!
      other_email.verify!

      assert_same_elements \
        @org_admin.notifiable_emails.to_a,
        @org.notifiable_emails_for(@org_admin).map(&:email)
    end

    test "returns notifiable emails for random user" do
      rando = create(:user)
      emails = @org.notifiable_emails_for(rando).map(&:email)
      assert_same_elements emails, rando.notifiable_emails.to_a
    end

    test "returns notifiable emails for outside collaborator" do
      collab = create(:user)
      @repo.add_member(collab)
      assert @repo.member?(collab)

      emails = @org.notifiable_emails_for(collab).map(&:email)
      assert_same_elements emails, collab.notifiable_emails.to_a
    end

    test "returns nothing if user not present" do
      assert_empty @org.notifiable_emails_for(nil)
    end
  end

  context "#supports_showing_verified_domain_emails?" do
    if GitHub.terms_of_service_enabled?
      test "returns true for org on supported plan and on corporate ToS" do
        assert @org.plan_supports?(:display_verified_domain_emails)
        assert_predicate @org.terms_of_service, :corporate?
        assert_predicate @org, :supports_showing_verified_domain_emails?
      end

      test "returns true for org on supported plan and on evaluation ToS" do
        @org.terms_of_service.update(type: "Evaluation", actor: @org_admin)
        assert @org.plan_supports?(:display_verified_domain_emails)
        assert_predicate @org.terms_of_service, :evaluation?
        assert_predicate @org, :supports_showing_verified_domain_emails?
      end

      test "returns true for org on supported plan and on custom ToS" do
        @org.terms_of_service.update(type: "Custom", actor: @org_admin)

        assert @org.plan_supports?(:display_verified_domain_emails)
        assert_predicate @org.terms_of_service, :custom?
        assert_predicate @org, :supports_showing_verified_domain_emails?
      end

      test "returns true for org owned by enterprise account regardless of ToS" do
        @business_owned_org.terms_of_service.update(type: "ESA+Education", actor: @org_admin)
        assert @business_owned_org.plan_supports?(:display_verified_domain_emails)
        assert_predicate @business_owned_org, :supports_showing_verified_domain_emails?
      end

      test "returns false for org not on business or custom ToS" do
        @org.terms_of_service.update(type: "Standard", actor: @org_admin)

        assert @org.plan_supports?(:display_verified_domain_emails)
        assert_predicate @org.terms_of_service, :standard?
        refute_predicate @org, :supports_showing_verified_domain_emails?
      end

      test "returns false for org on ESA+Education ToS" do
        @org.terms_of_service.update(type: "ESA+Education", actor: @org_admin)
        assert @org.plan_supports?(:display_verified_domain_emails)
        assert_predicate @org.terms_of_service, :esa_education?
        refute_predicate @org, :supports_showing_verified_domain_emails?
      end

      test "returns false for org not on supported plan" do
        org = create(:organization)
        org.terms_of_service.update(type: "Corporate", actor: @org_admin)

        refute org.plan_supports?(:display_verified_domain_emails)
        assert_predicate org.terms_of_service, :corporate?
        refute_predicate org, :supports_showing_verified_domain_emails?
      end
    else
      test "returns true for org in GHES where ToS are disabled" do
        assert @business_owned_org.plan_supports?(:display_verified_domain_emails)
        assert_predicate @business_owned_org, :supports_showing_verified_domain_emails?
      end
    end
  end

  context "#async_can_view_domain_emails?" do
    test "returns true for org owner" do
      assert @org.async_can_view_domain_emails?(@org_admin).sync
    end

    test "returns true for app with read members permission" do
      installation = make_integration_installation(
        target: @org,
        permissions: { "members" => :read }
      )

      assert @org.async_can_view_domain_emails?(installation).sync
    end

    test "returns false for app without read members permission" do
      installation = make_integration_installation(
        target: @org,
        permissions: { "metadata" => :read }
      )

      refute @org.async_can_view_domain_emails?(installation).sync
    end

    test "returns false for org member" do
      member = create(:user)
      @org.add_member(member)
      assert @org.member?(member)
      refute @org.async_can_view_domain_emails?(member).sync
    end

    test "returns false for random user" do
      refute @org.async_can_view_domain_emails?(create(:user)).sync
    end
  end

  context "#user_has_email_eligible_domain_notification_email?" do
    test "true for user with verified domain that matches org domain" do
      @org_admin.add_email("alice@sombra.example.com").verify!
      assert @restricted_org.user_has_email_eligible_domain_notification_email?(@org_admin)
    end

    test "false for user without verified domain that matches org domain" do
      user = create(:user)
      user.add_email("bob@example.com").verify!
      refute @restricted_org.user_has_email_eligible_domain_notification_email?(user)
    end

    test "false for user with email that matches org domain but is not verified" do
      user = create(:user)
      user.add_email("orisa@sombra.example.com")
      refute @restricted_org.user_has_email_eligible_domain_notification_email?(user)
    end
  end

  context "#user_can_receive_email_notifications?" do
    test "true for admin with verified domain configured that matches org domain" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "alice@sombra.example.com"
      @org_admin.add_email(email).verify!

      GitHub.newsies.get_and_update_settings(@org_admin) do |settings|
        settings.email @restricted_org, email
      end

      assert_equal email, GitHub.newsies.settings(@org_admin).email(@restricted_org).address
      assert @restricted_org.user_can_receive_email_notifications?(@org_admin)
    end

    test "true for member with verified domain configured that matches org domain" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "bob@sombra.example.com"
      @member.add_email(email).verify!

      GitHub.newsies.get_and_update_settings(@member) do |settings|
        settings.email @restricted_org, email
      end

      assert_equal email, GitHub.newsies.settings(@member).email(@restricted_org).address
      assert @restricted_org.user_can_receive_email_notifications?(@member)
    end

    test "true when member email has different case to org domain, where member email is mixed case" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "bob@SOMBRA.example.com"
      @member.add_email(email).verify!

      GitHub.newsies.get_and_update_settings(@member) do |settings|
        settings.email @restricted_org, email
      end

      assert_equal email, GitHub.newsies.settings(@member).email(@restricted_org).address
      assert @restricted_org.user_can_receive_email_notifications?(@member)
    end

    test "true when member email has different case to org domain, where org domain is mixed case" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "bob@somethingelse.com"
      @member.add_email(email).verify!

      GitHub.newsies.get_and_update_settings(@member) do |settings|
        settings.email @restricted_org, email
      end

      assert_equal email, GitHub.newsies.settings(@member).email(@restricted_org).address
      assert @restricted_org.user_can_receive_email_notifications?(@member)
    end

    test "true for collaborator without verified email" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      assert @restricted_org.user_can_receive_email_notifications?(@collab)
    end

    test "true for non-member" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      assert @restricted_org.user_can_receive_email_notifications?(create(:user))
    end

    test "false for member without verified email" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      @member.add_email("ashe@sombra.example.com")
      refute @restricted_org.user_can_receive_email_notifications?(@member)
    end

    test "false for member with verified email but not configured for routing" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "bob@sombra.example.com"
      @member.add_email(email).verify!

      refute_equal email, GitHub.newsies.settings(@member).email(@restricted_org).address
      refute @restricted_org.user_can_receive_email_notifications?(@member)
    end

    test "false if newsies is unavailable" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "alice@sombra.example.com"
      @org_admin.add_email(email).verify!

      GitHub.newsies.get_and_update_settings(@org_admin) do |settings|
        settings.email @restricted_org, email
      end

      assert_equal email, GitHub.newsies.settings(@org_admin).email(@restricted_org).address
      assert @restricted_org.user_can_receive_email_notifications?(@org_admin)

      newsies_response = Newsies::Responses::Array.new do
        raise Resiliency::Response::UnavailableExceptions.first
      end
      @org_admin.stubs(:newsies_settings_response).returns(newsies_response)

      refute @restricted_org.user_can_receive_email_notifications?(@org_admin)
    end

    test "false for member with unverified domain email configured" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "bob@sombra.example.com"
      @member.add_email(email).verify!

      GitHub.newsies.get_and_update_settings(@member) do |settings|
        settings.email @restricted_org, "bob@some-other-domain.example.com"
      end

      assert_equal "bob@some-other-domain.example.com",
                   GitHub.newsies.settings(@member).email(@restricted_org).address
      refute @restricted_org.user_can_receive_email_notifications?(@member)
    end

    test "false if email is not valid" do
      assert @restricted_org.restrict_notifications_to_verified_domains?

      GitHub.newsies.get_and_update_settings(@member) do |settings|
        settings.email @restricted_org, "notvalid&%"
      end

      assert_equal "notvalid&%", GitHub.newsies.settings(@member).email(@restricted_org).address
      refute @restricted_org.user_can_receive_email_notifications?(@member)
    end

    test "false for member who has a verified domain email address for the org, but that email's domain has not been verified" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "bob@sombra.example.com"
      @member.add_email(email).verify!
      create(:verifiable_domain, domain: "some-other-domain.example.com", owner: @restricted_org)
      @restricted_org.reload

      GitHub.newsies.get_and_update_settings(@member) do |settings|
        settings.email @restricted_org, "bob@some-other-domain.example.com"
      end

      assert_equal "bob@some-other-domain.example.com",
                   GitHub.newsies.settings(@member).email(@restricted_org).address
      refute @restricted_org.user_can_receive_email_notifications?(@member)
    end

    context "when org from business has set restricted email notifications to eligible domain emails" do
      context "when the user is a member of a different org from the business" do
        test "returns false for user with email domain that does not match the enterprise's domain" do
          member = create(:user, :verified, email: "bob@dogs.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          other_org = create :organization, admins: [@business_owner], business: @business
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          # add user to the other org
          other_org.add_member(member)
          other_org.reload
          org.reload

          assert org.enable_notification_restrictions(actor: @business_owner)

          # org has the restriction, so the user shouldn't receive any emails
          assert org.restrict_notifications_to_verified_domains?
          refute org.user_can_receive_email_notifications?(member)

          # other_org does not have the restriction, so the user should receive any emails
          refute other_org.restrict_notifications_to_verified_domains?
          assert other_org.user_can_receive_email_notifications?(member)
        end

        test "returns true for user with email domain that matches the enterprise's domain" do
          member = create(:user, :verified, email: "bob@cats.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          other_org = create :organization, admins: [@business_owner], business: @business
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          # add user to the other org
          other_org.add_member(member)
          other_org.reload
          org.reload

          assert org.enable_notification_restrictions(actor: @business_owner)

          # org has the restriction, but the user should receive emails
          assert org.restrict_notifications_to_verified_domains?
          assert org.user_can_receive_email_notifications?(member)
        end
      end

      context "when the user is a direct business member only" do
        test "return false for user with email domain that does not match the enterprise's domain" do
          member = create(:user, :verified, email: "bob@dogs.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          @business.add_owner(member, actor: @business_owner)
          org.reload

          assert org.enable_notification_restrictions(actor: @business_owner)

          # org has the restriction, so the user shouldn't receive any emails
          assert org.restrict_notifications_to_verified_domains?
          refute org.user_can_receive_email_notifications?(member)
        end

        test "returns true for user with email domain that matches the enterprise's domain" do
          member = create(:user, :verified, email: "bob@cats.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          @business.add_owner(member, actor: @business_owner)
          org.reload

          assert org.enable_notification_restrictions(actor: @business_owner)

          # org has the restriction, so the user shouldn't receive any emails
          assert org.restrict_notifications_to_verified_domains?
          assert org.user_can_receive_email_notifications?(member)
        end
      end

      context "when an outside collaborator is added to a repo" do
        test "returns true for outside collaborator with email domain that does not match the enterprise's domain" do
          collaborator = create(:user, :verified, email: "bob@dogs.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          other_org = create :organization, admins: [@business_owner], business: @business
          repo = create(:repository, owner: other_org)
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          # add user to the other org
          repo.add_member(collaborator)
          other_org.reload
          org.reload

          assert org.enable_notification_restrictions(actor: @business_owner)

          assert org.restrict_notifications_to_verified_domains?
          assert org.user_can_receive_email_notifications?(collaborator)

          refute other_org.restrict_notifications_to_verified_domains?
          assert other_org.user_can_receive_email_notifications?(collaborator)
        end
      end

      context "when the user is a non-member" do
        test "returns true for non-members with email domain that does not match the enterprise's domain" do
          rando = create(:user, :verified, email: "bob@dogs.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          org.reload

          assert org.enable_notification_restrictions(actor: @business_owner)

          assert org.restrict_notifications_to_verified_domains?
          assert org.user_can_receive_email_notifications?(rando)
        end
      end
    end

    context "when business has set restricted email notifications to eligible domain emails" do
      context "when the user is a member of an org from the business" do
        test "returns false for user with email domain that does not match the enterprise's domain" do
          member = create(:user, :verified, email: "bob@dogs.com")
          org = create :organization, admins: [@business_owner], business: @business
          other_org = create :organization, admins: [@business_owner], business: @business
          domain = create :verifiable_domain, owner: @business, domain: "cats.com", verified: true

          # add user to the other org
          other_org.add_member(member)
          other_org.reload
          org.reload

          assert_difference("Configuration::Entry.count") do
            assert @business.enable_notification_restrictions(actor: @business_owner)
          end

          assert @business.restrict_notifications_to_verified_domains?
          assert @business.config.get(Configurable::RestrictNotificationDelivery::KEY)

          # each org can have their restrictions but if the enterprise has the restriction,
          # that should take precedence over org's restrictions
          assert org.restrict_notifications_to_verified_domains?
          assert other_org.restrict_notifications_to_verified_domains?
          # the org's enterprise has the restriction, so the user shouldn't receive any emails
          refute org.user_can_receive_email_notifications?(member)
        end

        test "returns true for user with email domain that matches the enterprise's domain" do
          member = create(:user, :verified, email: "bob@cats.com")
          org = create :organization, admins: [@business_owner], business: @business
          other_org = create :organization, admins: [@business_owner], business: @business
          domain = create :verifiable_domain, owner: @business, domain: "cats.com", verified: true

          # add user to the other org
          other_org.add_member(member)
          other_org.reload
          org.reload

          assert_difference("Configuration::Entry.count") do
            assert @business.enable_notification_restrictions(actor: @business_owner)
          end

          assert @business.restrict_notifications_to_verified_domains?
          assert @business.config.get(Configurable::RestrictNotificationDelivery::KEY)

          # each org can have their restrictions but if the enterprise has the restriction,
          # that should take precedence over org's restrictions
          assert org.restrict_notifications_to_verified_domains?
          assert other_org.restrict_notifications_to_verified_domains?
          # the org's enterprise has the restriction, but the user should still receive emails
          assert org.user_can_receive_email_notifications?(member)
        end
      end

      context "when the user is a direct business member only" do
        test "return false for user with email domain that does not match the enterprise's domain" do
          member = create(:user, :verified, email: "bob@dogs.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          @business.add_owner(member, actor: @business_owner)
          org.reload

          assert_difference("Configuration::Entry.count") do
            assert @business.enable_notification_restrictions(actor: @business_owner)
          end

          assert @business.restrict_notifications_to_verified_domains?
          assert @business.config.get(Configurable::RestrictNotificationDelivery::KEY)

          assert org.restrict_notifications_to_verified_domains?
          refute org.user_can_receive_email_notifications?(member)
        end

        test "returns true for user with email domain that matches the enterprise's domain" do
          member = create(:user, :verified, email: "bob@cats.com")
          org = create(:business_plus_organization, admins: [@business_owner], business: @business)
          domain = create :verifiable_domain, owner: org, domain: "cats.com", verified: true

          @business.add_owner(member, actor: @business_owner)
          org.reload

          assert_difference("Configuration::Entry.count") do
            assert @business.enable_notification_restrictions(actor: @business_owner)
          end

          assert @business.restrict_notifications_to_verified_domains?
          assert @business.config.get(Configurable::RestrictNotificationDelivery::KEY)

          assert org.restrict_notifications_to_verified_domains?
          assert org.user_can_receive_email_notifications?(member)
        end
      end

      context "when an outside collaborator is added to a repo" do
        test "returns true for outside collaborator with email domain that does not match the enterprise's domain" do
          collaborator = create(:user, :verified, email: "bob@dogs.com")
          org = create :organization, admins: [@business_owner], business: @business
          other_org = create :organization, admins: [@business_owner], business: @business
          repo = create(:repository, owner: other_org)
          domain = create :verifiable_domain, owner: @business, domain: "cats.com", verified: true

          # add user to the other org
          repo.add_member(collaborator)
          other_org.reload
          org.reload

          assert_difference("Configuration::Entry.count") do
            assert @business.enable_notification_restrictions(actor: @business_owner)
          end

          assert @business.restrict_notifications_to_verified_domains?
          assert @business.config.get(Configurable::RestrictNotificationDelivery::KEY)

          # each org can have their restrictions but if the enterprise has the restriction,
          # that should take precedence over org's restrictions
          assert org.restrict_notifications_to_verified_domains?
          assert other_org.restrict_notifications_to_verified_domains?
          # the org's enterprise has the restriction, but this doesn't apply to outside collaborators
          # as based in this comment:
          # https://github.com/github/github/blob/master/packages/enterprise/app/models/organization/notification_restrictions_dependency.rb#L131
          assert org.user_can_receive_email_notifications?(collaborator)
        end
      end

      context "when the user is a non-member" do
        test "returns true for non-members with email domain that does not match the enterprise's domain" do
          rando = create(:user, :verified, email: "bob@dogs.com")
          org = create :organization, admins: [@business_owner], business: @business
          domain = create :verifiable_domain, owner: @business, domain: "cats.com", verified: true

          org.reload

          assert_difference("Configuration::Entry.count") do
            assert @business.enable_notification_restrictions(actor: @business_owner)
          end

          assert @business.restrict_notifications_to_verified_domains?
          assert @business.config.get(Configurable::RestrictNotificationDelivery::KEY)

          # each org can have their restrictions but if the enterprise has the restriction,
          # that should take precedence over org's restrictions
          assert org.restrict_notifications_to_verified_domains?
          # the org's enterprise has the restriction, but this doesn't apply to non-members
          # as based in this comment:
          # https://github.com/github/github/blob/master/packages/enterprise/app/models/organization/notification_restrictions_dependency.rb#L131
          assert org.user_can_receive_email_notifications?(rando)
        end
      end
    end
  end

  context "#show_notification_restriction_banner?" do
    test "true for member without verified email configured" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      refute @restricted_org.user_can_receive_email_notifications?(@member)
      settings = GitHub.newsies.settings(@member)
      assert_predicate settings, :participating_email?
      assert_predicate settings, :subscribed_email?

      assert @restricted_org.show_notification_restriction_banner?(@member)
    end

    test "false for member with verified domain configured that matches org domain" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      email = "alice@sombra.example.com"
      @org_admin.add_email(email).verify!

      GitHub.newsies.get_and_update_settings(@org_admin) do |settings|
        settings.email @restricted_org, email
      end

      settings = GitHub.newsies.settings(@org_admin)
      assert_predicate settings, :participating_email?
      assert_predicate settings, :subscribed_email?
      assert_equal email, settings.email(@restricted_org).address

      refute @restricted_org.show_notification_restriction_banner?(@org_admin)
    end

    test "false for outside collaborator" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      assert @restricted_org.user_can_receive_email_notifications?(@collab)
      settings = GitHub.newsies.settings(@collab)
      assert_predicate settings, :participating_email?
      assert_predicate settings, :subscribed_email?

      refute @restricted_org.show_notification_restriction_banner?(@collab)
    end

    test "false for member who does not receive email notifications" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      refute @restricted_org.user_can_receive_email_notifications?(@member)

      enable_notifications_for_user(@member, enabled_handlers: ["web"])

      settings = GitHub.newsies.settings(@member)
      refute_predicate settings, :participating_email?
      refute_predicate settings, :subscribed_email?

      refute @restricted_org.show_notification_restriction_banner?(@member)
    end

    test "false if newsies is unavailable" do
      assert @restricted_org.restrict_notifications_to_verified_domains?
      refute @restricted_org.user_can_receive_email_notifications?(@org_admin)

      newsies_response = Newsies::Responses::Array.new do
        raise Resiliency::Response::UnavailableExceptions.first
      end
      GitHub.newsies.stubs(:settings).returns(newsies_response)

      refute @restricted_org.show_notification_restriction_banner?(@org_admin)
    end
  end
end
