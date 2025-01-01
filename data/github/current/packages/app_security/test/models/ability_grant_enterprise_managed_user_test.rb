# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/ability_helper"
require "test_helpers/ability_models"

unless GitHub.single_business_environment?
  class AbilityGrantEnterpriseManagedUserTest < GitHub::TestCase
    include AbilityHelper

    fixtures do
      @user      = create(:user)
      @user_repo = create(:repository, :minimal, owner: @user)
      @org       = create(:business_plus_organization)

      @org_repo  = create(:repository, :minimal, owner: @org)

      @other_repo = create(:private_repository, :minimal)

      @biz_org  = create(:enterprise_linked_organization)
      @biz      = @biz_org.business
      @biz_repo = create(:private_repository, :minimal, owner: @biz_org)

      @emu_admin = create(:emu, :owner)
      @emu_biz   = @emu_admin.enterprise_managed_business
      @emu       = create(:emu, business: @emu_biz)

      @emu_org   = create :enterprise_linked_organization, business: @emu_biz, admin: @emu
      @emu_repo  = create(:private_repository, :minimal, owner: @emu_org)

      @emu_owned_repo = create(:private_repository, :minimal, owner: @emu)

      @emu2     = create(:emu, business: @emu_biz)
      @emu_org.add_member(@emu2)

      @other_emu     = create(:emu)
      @other_emu_org = create :enterprise_linked_organization,
                              business: @other_emu.enterprise_managed_business,
                              admin: @other_emu
    end

    test "grants when actor is not a user" do
      ability = grant_ability(actor: AnActor.create, subject: @org_repo, action: :write)
      assert ability.valid?
    end

    test "grants when actor is not an EMU" do
      ability = grant_ability(actor: @user, subject: @org_repo, action: :write)
      assert ability.valid?
    end

    test "valid when the subject belongs to a user" do
      ability = grant_ability(actor: @user, subject: @other_repo, action: :write)
      assert ability.valid?
    end

    test "valid when the subject belongs to a regular org" do
      ability = grant_ability(actor: @user, subject: @org, action: :admin)
      assert ability.valid?
    end

    test "valid when the subject belongs to a regular business" do
      ability = grant_ability(actor: @user, subject: @biz, action: :admin)
      assert ability.valid?
    end

    context "with an EMU" do
      context "over a user owned resource" do
        test "raises when subject is not part of a business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @user_repo, action: :write)
          end
        end

        test "raises when subject is not part of the EMUs owning business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @other_emu, subject: @emu_owned_repo, action: :write)
          end
        end

        test "valid when subject is part of the EMU owning business" do
          ability = grant_ability(actor: @emu2, subject: @emu_owned_repo, action: :write)
          assert ability.valid?
        end
      end

      context "over an org owned resource" do
        test "raises when subject is not part of a business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @org_repo, action: :write)
          end
        end

        test "raises when subject is not part of the EMUs owning business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @biz_repo, action: :write)
          end
        end

        test "valid when subject is part of the EMU owning business" do
          ability = grant_ability(actor: @emu, subject: @emu_repo, action: :write)
          assert ability.valid?
        end

        test "raises when org is not part of a business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @org, action: :admin)
          end
        end

        test "raises when org is not part of the EMUs owning business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @biz_org, action: :admin)
          end
        end

        test "raises when EMU org is not part of the EMUs owning business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @other_emu.organizations.first, action: :admin)
          end
        end

        test "valid when org is part of the EMU owning business" do
          ability = grant_ability(actor: @emu, subject: @emu_org, action: :admin)
          assert ability.valid?
        end

        test "valid when a new org is being created by an EMU admin with no associated business" do
          new_emu_org = Organization.new({
            login: "new-org",
            billing_email: "admin@github.com",
          })
          new_emu_org.creator = @emu_admin
          new_emu_org.associated_business_on_creation = @emu_biz
          new_emu_org.admins = [@emu_admin]
          new_emu_org.save
          ability = grant_ability(actor: @emu_admin, subject: new_emu_org, action: :admin)
          assert ability.valid?
        end

        test "raises when a new org is being created by a normal EMU user and no business" do
          new_emu_org = Organization.new({
            login: "new-org",
            billing_email: "admin@github.com",
          })
          new_emu_org.creator = @emu2
          new_emu_org.admins = [@emu2]

          assert_raises Permissions::Participant::PermissionGrantError do
            new_emu_org.save
          end
        end

        test "raises when a new org is created by a normal user and no business and an EMU is attempted to be granted admin" do
          new_user_org = Organization.new({
            login: "new-user-org",
            billing_email: "admin@github.com",
          })

          new_user_org.creator = @user
          new_user_org.admins = [@user]
          new_user_org.save

          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu2, subject: new_user_org, action: :admin)
          end
        end
      end

      context "over a business owned resource" do
        test "raises when business is not part of the EMUs owning business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @biz, action: :admin)
          end
        end

        test "raises when EMU business is not the sam as actor's EMU business" do
          assert_raises ::Permissions::Participant::PermissionGrantError do
            grant_ability(actor: @emu, subject: @other_emu.enterprise_managed_business, action: :admin)
          end
        end

        test "valid when business is part of the EMU owning business" do
          ability = grant_ability(actor: @emu, subject: @emu_biz, action: :admin)
          assert ability.valid?
        end
      end
    end
  end
end
