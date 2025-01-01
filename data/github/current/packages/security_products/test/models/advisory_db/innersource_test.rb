# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDbInnersourceTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @business = create(:business)
    @org = create(:organization, admin: @user, business: @business)
    @public_repo = create(:repository, owner: @org)
    @private_repo = create(:private_repository, owner: @org)
  end

  def setup
    disable_feature_flag(:private_advisories_disabled, @private_repo)
    enable_feature_flag(:private_advisories_disabled)
    disable_feature_flag(:innersource_advisories)
    @org.advanced_security_billable_entity.stubs(:advanced_security_purchased?).returns(true)

    @subject = AdvisoryDB::Innersource
  end

  def teardown
    disable_feature_flag(:private_advisories_disabled)
  end

  def enable_advanced_security(repo:)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
  end

  def disable_advanced_security(repo:)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(false)
  end

  context "#private_advisory_exempt_repo?" do
    if GitHub.single_or_multi_tenant_enterprise?
      test "exempt on enterprise because private advisories aren't supported there" do
        assert @subject.private_advisory_exempt_repo?(repo: @public_repo)
        assert @subject.private_advisory_exempt_repo?(repo: @private_repo)
      end
    else
      test "not exempt on public repo" do
        refute @subject.private_advisory_exempt_repo?(repo: @public_repo)
      end

      test "exempt on private repo" do
        assert @subject.private_advisory_exempt_repo?(repo: @private_repo)
      end

      context "feature flag checks" do
        test "not exempt on any repo if FF disabled" do
          disable_feature_flag(:private_advisories_disabled)

          refute @subject.private_advisory_exempt_repo?(repo: @private_repo)
          refute @subject.private_advisory_exempt_repo?(repo: @public_repo)
        end

        test "exempt on private repo if FF enabled on repo" do
          disable_feature_flag(:private_advisories_disabled)
          enable_feature_flag(:private_advisories_disabled, @private_repo)

          assert @subject.private_advisory_exempt_repo?(repo: @private_repo)
        end

        test "exempt on private repo if FF enabled on org" do
          disable_feature_flag(:private_advisories_disabled)
          enable_feature_flag(:private_advisories_disabled, @org)

          assert @subject.private_advisory_exempt_repo?(repo: @private_repo)
        end
      end
    end
  end

  context "#eligible_repo?" do
    test "archived repos are not authorized" do
      enable_feature_flag(:innersource_advisories, @org)
      archived_repo = create(:public_repository, owner: @user)
      archived_repo.set_archived

      refute @subject.eligible_repo?(repo: archived_repo)
    end

    unless GitHub.single_or_multi_tenant_enterprise?
      context "dotcom" do
        test "repo is authorized if FF is enabled on org, GHAS enabled, and repo is private" do
          enable_feature_flag(:innersource_advisories, @org)
          enable_advanced_security(repo: @private_repo)

          assert @subject.eligible_repo?(repo: @private_repo)

          disable_advanced_security(repo: @private_repo)
          disable_feature_flag(:innersource_advisories, @org)
        end

        test "repo is not authorized if FF is disabled on org" do
          disable_feature_flag(:innersource_advisories, @org)
          enable_advanced_security(repo: @private_repo)

          refute @subject.eligible_repo?(repo: @private_repo)

          disable_advanced_security(repo: @private_repo)
        end

        test "repo is not authorized if GHAS is not enabled on repo" do
          enable_feature_flag(:innersource_advisories, @org)
          disable_advanced_security(repo: @private_repo)

          refute @subject.eligible_repo?(repo: @private_repo)

          disable_feature_flag(:innersource_advisories, @org)
        end

        test "repo is not authorized if repo is not private" do
          enable_feature_flag(:innersource_advisories, @org)
          enable_advanced_security(repo: @public_repo)

          refute @subject.eligible_repo?(repo: @public_repo)

          disable_advanced_security(repo: @public_repo)
          disable_feature_flag(:innersource_advisories, @org)
        end
      end
    end

    # TODO: split this into enterprise/proxima sections once we release this for GHES.
    if GitHub.multi_tenant_enterprise?
      context "multitenant" do
        test "repo is authorized if FF is enabled on org and GHAS enabled" do
          enable_feature_flag(:innersource_advisories, @org)
          enable_advanced_security(repo: @public_repo)

          assert @subject.eligible_repo?(repo: @public_repo)

          disable_feature_flag(:innersource_advisories, @org)
          disable_advanced_security(repo: @public_repo)
        end

        test "repo is not authorized if FF is disabled on org" do
          disable_feature_flag(:innersource_advisories, @org)
          enable_advanced_security(repo: @public_repo)

          refute @subject.eligible_repo?(repo: @public_repo)

          disable_advanced_security(repo: @public_repo)
        end

        test "repo is not authorized if GHAS is not enabled on repo" do
          enable_feature_flag(:innersource_advisories, @org)
          disable_advanced_security(repo: @public_repo)

          refute @subject.eligible_repo?(repo: @public_repo)
        end
      end
    end
  end

  context "#org_authorized?" do
    unless GitHub.enterprise?
      test "org is authorized if FF enabled on org and GHAS purchased" do
        enable_feature_flag(:innersource_advisories, @org)
        assert @subject.org_authorized?(org: @org)
        disable_feature_flag(:innersource_advisories, @org)
      end

      test "org is authorized if FF enabled on parent business" do
        enable_feature_flag(:innersource_advisories, @business)
        assert @subject.org_authorized?(org: @org)
        disable_feature_flag(:innersource_advisories, @business)
      end

      test "org is authorized if FF enabled on org but not on parent business" do
        enable_feature_flag(:innersource_advisories, @org)
        disable_feature_flag(:innersource_advisories, @business)
        assert @subject.org_authorized?(org: @org)
        disable_feature_flag(:innersource_advisories, @org)
      end

      test "org is authorized if FF enabled on parent business but not on org" do
        enable_feature_flag(:innersource_advisories, @business)
        disable_feature_flag(:innersource_advisories, @org)
        assert @subject.org_authorized?(org: @org)
        disable_feature_flag(:innersource_advisories, @business)
      end

      test "org is not authorized if FF is disabled on both org and parent business" do
        disable_feature_flag(:innersource_advisories, @business)
        disable_feature_flag(:innersource_advisories, @org)
        refute @subject.org_authorized?(org: @org)
      end

      test "org is not authorized if GHAS is not purchased" do
        @org.advanced_security_billable_entity.stubs(:advanced_security_purchased?).returns(false)

        refute @subject.org_authorized?(org: @org)
      end
    end
  end

  context "#business_authorized?" do
    unless GitHub.enterprise?
      test "business is authorized if FF enabled and GHAS purchased" do
        enable_feature_flag(:innersource_advisories, @business)
        Business.any_instance.stubs(:advanced_security_purchased_for_entity?).returns(true)
        assert @subject.business_authorized?(business: @business)
        disable_feature_flag(:innersource_advisories, @business)
      end

      test "business is unauthorized if FF disabled" do
        disable_feature_flag(:innersource_advisories, @business)
        Business.any_instance.stubs(:advanced_security_purchased_for_entity?).returns(true)
        refute @subject.business_authorized?(business: @business)
      end

      test "business is unauthorized if GHAS is not purchased" do
        enable_feature_flag(:innersource_advisories, @business)
        Business.any_instance.stubs(:advanced_security_purchased_for_entity?).returns(false)
        refute @subject.business_authorized?(business: @business)
        disable_feature_flag(:innersource_advisories, @business)
      end
    end
  end
end
