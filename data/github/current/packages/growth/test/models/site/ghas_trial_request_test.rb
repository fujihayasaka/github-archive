# typed: true
# frozen_string_literal: true

require "test_helper"

class GhasTrialRequestTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @name = "monalisa"
    @valid_email = "example@github.com"
    @utm_campaign = "ghas_trial_request"
    @country = "US"
    @utm_medium = "email"
    @utm_source = "github"
    @utm_content = "business_plus"
    @invalid_email = "examplegithub.com"

    @cdl_program_name = GitHub.ghas_trial_campaign_id
    @source = GitHub.ghas_trial_source.presence || GitHub.ghas_trial_campaign_id
    @sf_campaign_status = GitHub.ghas_trial_status

    @requester = create(:user)
    @eligible_org = create(:credit_card_organization, name: "GitHub", admin: @requester)
    @not_eligible_org = create(:organization, admin: @requester, name: "NotEligible")

    @invoiced_owner = create(:user)
    @invoiced_business = create(:business, owners: [@invoiced_owner])
    @org_admin = create(:user)
    @invoiced_child_org = create(:enterprise_linked_organization, admin: @org_admin, business: @invoiced_business)
  end

  test "can create valid GHAS trial request" do
    ghas_trial_request = Site::GhasTrialRequest.new(
      name: @name,
      email: @valid_email,
      requester: @requester,
      organization: @eligible_org
    )
    assert_predicate ghas_trial_request, :valid?
  end

  test "email is required" do
    ghas_trial_request = Site::GhasTrialRequest.new(
      name: @name,
      email: "",
      requester: @requester,
      organization: @eligible_org
    )
    refute_predicate ghas_trial_request, :valid?
    assert ghas_trial_request.errors[:email].present?
  end

  test "organization is required" do
    ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester)
    refute_predicate ghas_trial_request, :valid?
    assert ghas_trial_request.errors[:organization].present?
  end

  test "email must be valid" do
    ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @invalid_email, requester: @requester, organization: @eligible_org)
    refute_predicate ghas_trial_request, :valid?
    assert ghas_trial_request.errors[:email].present?
  end

  test "marketing_email_opt_in is present and valid" do
    ghas_trial_request = Site::GhasTrialRequest.new(
       name: @name,
       email: @valid_email,
       requester: @requester,
       marketing_email_opt_in: 1,
       organization: @eligible_org
    )
    assert_predicate ghas_trial_request, :valid?
    assert ghas_trial_request.marketing_email_opt_in, 1
  end

  context "#save" do
    test "does nothing if request is invalid" do
      @eligible_org.add_member(@requester)
      ghas_trial_request = Site::GhasTrialRequest.new(name: "", email: @valid_email, requester: @requester, organization: @eligible_org)

      MarketingFormsSubmissionJob.expects(:perform_later).never
      refute_hydro_messages(schema: "github.octogrowth.v0.GhasTrialRequest")

      ghas_trial_request.save
    end

    test "does nothing if request can_send_request? is false" do
      ghas_trial_request = Site::GhasTrialRequest.new(
        name: @name,
        email: @valid_email,
        country: @country,
        marketing_email_opt_in: 1,
        utm_campaign: @utm_campaign,
        utm_medium: @utm_medium,
        utm_source: @utm_source,
        utm_content: @utm_content,
        requester: @requester,
        organization: @eligible_org
      )
      ghas_trial_request.expects(:can_send_request?).returns(false)

      MarketingFormsSubmissionJob.expects(:perform_later).never
      refute_hydro_messages(schema: "github.octogrowth.v0.GhasTrialRequest")

      ghas_trial_request.save
    end

    test "sends request if valid" do
      ghas_trial_request = Site::GhasTrialRequest.new(
        name: @name,
        email: @valid_email,
        country: @country,
        marketing_email_opt_in: 1,
        utm_campaign: @utm_campaign,
        utm_medium: @utm_medium,
        utm_source: @utm_source,
        utm_content: @utm_content,
        requester: @requester,
        organization: @eligible_org
      )

      ghas_trial_request.expects(:send_request).once

      ghas_trial_request.save
    end
  end

  context "#send_request" do
    test "it logs to eloqua even if the org has no ghas_trial eligiblity" do
      ghas_trial_request = Site::GhasTrialRequest.new(
        name: @name,
        email: @valid_email,
        requester: @requester,
        organization: @not_eligible_org
      )

      freeze_time do
        ghas_trial_request.send_request
        assert_hydro_published({
          organization_id: @not_eligible_org.id,
          submitted_at: Time.now.utc,
        }, schema: "github.octogrowth.v0.GhasTrialRequest")
      end
    end

    test "it enqueues marketing forms submission job" do
      @eligible_org.add_member(@requester)
      ghas_trial_request = Site::GhasTrialRequest.new(
        name: @name,
        email: @valid_email,
        country: @country,
        marketing_email_opt_in: 1,
        utm_campaign: @utm_campaign,
        utm_medium: @utm_medium,
        utm_source: @utm_source,
        utm_content: @utm_content,
        requester: @requester,
        organization: @eligible_org
      )

      MarketingFormsSubmissionJob.expects(:perform_later).once.with(
        form_name: "ghas-trial",
        raw_data: {
          name: @name,
          email: @valid_email,
          country: @country,
          org_name: @eligible_org.name,
          marketingConsent: "optInExplicit",
          utm_campaign: @utm_campaign,
          utm_medium: @utm_medium,
          utm_source: @utm_source,
          utm_content: @utm_content,
          cDLProgramName: @cdl_program_name,
          source: @source,
          sFDCLastCampaignStatus: @sf_campaign_status,
        }
      ).returns(nil)

      ghas_trial_request.send_request
    end

    test "it logs to hydro" do
      @eligible_org.add_member(@requester)
      ghas_trial_request = Site::GhasTrialRequest.new(
        name: @name,
        email: @valid_email,
        requester: @requester,
        organization: @eligible_org,
      )

      freeze_time do
        ghas_trial_request.send_request

        assert_hydro_published({
          organization_id: @eligible_org.id,
          submitted_at: Time.now.utc,
        }, schema: "github.octogrowth.v0.GhasTrialRequest")
      end
    end
  end

  context "#can_send_request?" do
    test "it is false if there is no requester" do
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: nil, organization: @eligible_org)

      refute ghas_trial_request.can_send_request?
    end

    test "it is false if there is no org" do
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: nil)

      refute ghas_trial_request.can_send_request?
    end

    test "it is true if requester has no ghas eligible org" do
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: @not_eligible_org)

      assert ghas_trial_request.can_send_request?
    end

    test "it is true if requester has ghas eligible org" do
      @eligible_org.add_member(@requester)
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: @eligible_org)

      assert ghas_trial_request.can_send_request?
    end

    test "it is true if parent Business is eligible and requester can manage business" do
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @invoiced_owner, organization: @invoiced_child_org)
      assert ghas_trial_request.can_send_request?
    end

    test "it is true if parent Business is eligible and requester can manage org" do
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @org_admin, organization: @invoiced_child_org)
      assert ghas_trial_request.can_send_request?
    end

    test "it is false if parent Business is eligible and requester is not an admin of either entity" do
      member = create :user
      @invoiced_child_org.add_member(member)
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: member, organization: @invoiced_child_org)
      refute ghas_trial_request.can_send_request?
    end
  end

  test "#cdl_program_name" do
    ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: @eligible_org)
    assert_equal GitHub.ghas_trial_campaign_id, ghas_trial_request.cdl_program_name
  end

  context "#source" do
    test "from config value" do
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: @eligible_org)
      assert_equal GitHub.ghas_trial_source, ghas_trial_request.source
    end

    test "defaults to cdl_program_name" do
      GitHub.stubs(:ghas_trial_source).returns(nil)
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: @eligible_org)
      assert_equal ghas_trial_request.cdl_program_name, ghas_trial_request.source
    end

    test "uses default if configured value is blank" do
      ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: @eligible_org)
      GitHub.stubs(:ghas_trial_source).returns("")
      assert_equal ghas_trial_request.cdl_program_name, ghas_trial_request.source
    end
  end

  test "#salesforce_campaign_status" do
    ghas_trial_request = Site::GhasTrialRequest.new(name: @name, email: @valid_email, requester: @requester, organization: @eligible_org)
    assert_equal GitHub.ghas_trial_status, ghas_trial_request.salesforce_campaign_status
  end
end unless GitHub.enterprise?
