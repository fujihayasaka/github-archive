# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::Transfers::ValidatorTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @requester = @integration.owner
    @org_target = create(:organization)
  end

  def build_validator(integration: @integration, target: @org_target, stafftools_initiated: false)
    Integration::Transfers::Validator.new(
      integration: integration,
      target: target,
      stafftools_initiated: stafftools_initiated
    )
  end

  def get_biz
    if GitHub.single_business_environment?
      GitHub::Enterprise.ensure_business!
      GitHub.global_business
    else
      create(:business)
    end
  end

  def get_biz_and_member
    biz = get_biz

    if GitHub.single_business_environment?
      member = create(:user)
      org = create(:organization, admins: [member])
      biz.add_organization(org)
    else
      member = biz.members.first
    end

    [biz, member]
  end

  test "false when transfering to self" do
    validator = build_validator(target: @integration.owner)
    refute validator.valid?
  end

  test "true when no installations" do
    validator = build_validator
    assert validator.valid?
  end

  test "returns false when target is nil" do
    validator = build_validator(target: nil)
    refute validator.valid?
  end

  context "user to biz" do
    test "true when public EMU owned app to business" do
      emu_biz = create(:business, :enterprise_managed)
      emu = emu_biz.members.first
      integration = create(:integration, visibility: :public_visibility, owner: emu)
      validator = build_validator(integration: integration, target: emu_biz)
      assert validator.valid?
    end unless GitHub.single_business_environment?

    test "true when privately owned user app to business" do
      target, member = get_biz_and_member
      integration = create(:integration, :private, owner: member)
      installation = create(:integration_installation, integration: integration, target: target)
      validator = build_validator(integration: integration, target: target)
      assert validator.valid?
    end

    test "false when publicly owned user app to business" do
      target, member = get_biz_and_member
      integration = create(:integration, visibility: :public_visibility, owner: member)
      installation = create(:integration_installation, integration: integration, target: target)
      validator = build_validator(integration: integration, target: target)
      refute validator.valid?
    end

    test "false when publicly owned user app to business on stafftools" do
      target, member = get_biz_and_member
      integration = create(:integration, visibility: :public_visibility, owner: member)
      installation = create(:integration_installation, integration: integration, target: target)
      validator = build_validator(integration: integration, target: target, stafftools_initiated: true)
      refute validator.valid?
    end

    test "true when user member of business" do
      target, member = get_biz_and_member
      integration = create(:integration, :private, owner: member)
      validator = build_validator(integration: integration, target: target)
      assert validator.valid?
    end

    test "false when user to unaffiliated business" do
      target = get_biz
      refute target.member?(@requester)
      validator = build_validator(integration: @integration, target: target)
      refute validator.valid?
    end
  end

  context "org to biz" do
    test "true when public org owned EMU app to business" do
      emu_biz = create(:business, :enterprise_managed)
      emu = emu_biz.members.first
      org = create(:enterprise_linked_organization, business: emu_biz, admin: emu)
      integration = create(:integration, visibility: :public_visibility, owner: org)
      validator = build_validator(integration: integration, target: emu_biz)
      assert validator.valid?
    end unless GitHub.single_business_environment?

    test "true when private org owned app to business" do
      target, _ = get_biz_and_member
      org = create(:organization, business: target)
      integration = create(:integration, :private, owner: org)
      installation = create(:integration_installation, integration: integration, target: target)
      validator = build_validator(integration: integration, target: target)
      assert validator.valid?
    end

    test "false when public org owned app to business" do
      target, _ = get_biz_and_member
      org = create(:organization, business: target)
      integration = create(:integration, visibility: :public_visibility, owner: org)
      installation = create(:integration_installation, integration: integration, target: target)
      validator = build_validator(integration: integration, target: target)
      refute validator.valid?
    end

    test "false when public org owned app to business on stafftools" do
      target, _ = get_biz_and_member
      org = create(:organization, business: target)
      integration = create(:integration, visibility: :public_visibility, owner: org)
      installation = create(:integration_installation, integration: integration, target: target)
      validator = build_validator(integration: integration, target: target, stafftools_initiated: true)
      refute validator.valid?
    end

    test "true when org part of business" do
      target = get_biz
      org = create(:organization, business: target)
      integration = create(:integration, :private, owner: org)
      validator = build_validator(integration: integration, target: target)
      assert validator.valid?
    end

    test "false when org to unaffiliated business" do
      target = get_biz
      org = create(:organization)
      integration = create(:integration, :private, owner: org)
      validator = build_validator(integration: integration, target: target)
      refute validator.valid?
    end
  end

  context "biz to biz" do
    test "true when business owned app to business in stafftools" do
      owner = create(:business)
      target = create(:business)
      requester = create(:user, :staff)
      integration = create(:integration, visibility: :internal_visibility, owner: owner)
      validator = build_validator(integration: integration, target: target, stafftools_initiated: true)

      assert validator.valid?
    end unless GitHub.single_business_environment?

    test "false when business owned app with installations to business in stafftools" do
      owner = create(:business)
      target = create(:business)
      requester = create(:user, :staff)
      integration = create(:integration, visibility: :internal_visibility, owner: owner)
      installation = create(:integration_installation, integration: integration, target: target)
      validator = build_validator(integration: integration, target: target, stafftools_initiated: true)

      refute validator.valid?
    end unless GitHub.single_business_environment?

    test "false when non-stafftools business to business" do
      owner = create(:business)
      target = create(:business)
      requester = create(:user, :staff)
      integration = create(:integration, visibility: :internal_visibility, owner: owner)
      validator = build_validator(integration: integration, target: target, stafftools_initiated: false)
      refute validator.valid?
    end unless GitHub.single_business_environment?

    test "false when transfering EMU enabled org app to non EMU target", skip_if_feature_disabled: :integration_installable_on_with_emus_check do
      emu_biz = create(:business, :enterprise_managed)
      emu = emu_biz.members.first
      org = create(:enterprise_linked_organization, business: emu_biz, admin: emu)
      integration = create(:integration, visibility: :public_visibility, owner: org)
      non_emu = create(:user)
      validator = build_validator(integration: integration, target: non_emu)
      refute validator.valid?
    end unless GitHub.single_business_environment?
  end

  context "user to org" do
    test "true when public app" do
      integration = create(:integration, visibility: :public_visibility)
      validator = build_validator(integration: integration, target: @org_target)
      assert validator.valid?
    end

    test "true when private app" do
      integration = create(:integration, :private)
      validator = build_validator(integration: integration, target: @org_target)
      assert validator.valid?
    end

    test "true when private app with installation" do
      integration = create(:integration, :private)
      installation = create(:integration_installation, integration: integration, target: integration.owner)
      validator = build_validator(integration: integration, target: @org_target)
      assert validator
    end
  end

  context "user to user" do
    test "true when public app" do
      integration = create(:integration, visibility: :public_visibility)
      validator = build_validator(integration: integration, target: @requester)
      assert validator.valid?
    end

    test "true when private app" do
      integration = create(:integration, :private)
      validator = build_validator(integration: integration, target: @requester)
      assert validator.valid?
    end

    test "true when private app with installation" do
      integration = create(:integration, :private)
      installation = create(:integration_installation, integration: integration, target: integration.owner)
      validator = build_validator(integration: integration, target: @requester)
      assert validator.valid?
    end

    test "false when transfering EMU owned app to non EMU target", skip_if_feature_disabled: :integration_installable_on_with_emus_check do
      emu_biz = create(:business, :enterprise_managed)
      emu = emu_biz.members.first
      integration = create(:integration, visibility: :public_visibility, owner: emu)
      non_emu = create(:user)
      validator = build_validator(integration: integration, target: non_emu)
      refute validator.valid?
    end unless GitHub.single_business_environment?
  end

  context "org to org" do
    test "true when public app" do
      org = create(:organization)
      integration = create(:integration, visibility: :public_visibility, owner: org)
      validator = build_validator(integration: integration, target: @org_target)
      assert validator.valid?
    end

    test "true when private app" do
      org = create(:organization)
      integration = create(:integration, :private, owner: org)
      validator = build_validator(integration: integration, target: @org_target)
      assert validator.valid?
    end

    test "true when private app with installation" do
      org = create(:organization)
      integration = create(:integration, :private, owner: org)
      installation = create(:integration_installation, integration: integration, target: org)
      validator = build_validator(integration: integration, target: @org_target)
      assert validator.valid?
    end
  end
end
