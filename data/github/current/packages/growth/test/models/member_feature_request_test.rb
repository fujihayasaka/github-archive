# typed: strict
# frozen_string_literal: true

require "test_helper"

class MemberFeatureRequestTest < GitHub::TestCase
  include HydroTestHelpers
  include ActionMailer::TestHelper

  fixtures do
    @user = T.let(create(:user), T.nilable(User))
    @org_user = T.let(create(:user), T.nilable(User))
    @admin = T.let(create(:user), T.nilable(User))
    @repo = T.let(create(:repository), T.nilable(Repository))
    @request_entity = T.let(create(:organization, admin: @admin), T.nilable(Organization))

    T.must(@request_entity).add_member(@org_user)
    T.must(@request_entity).add_member(@admin)
  end

  context "validations" do
    test "validates the presence of the requester" do
      request = build(:member_feature_request, requester: nil)

      refute request.valid?
      assert request.errors[:requester].any?
    end

    test "validates the presence of the request_entity" do
      request = build(:member_feature_request, request_entity: nil)

      refute request.valid?
    end

    test "feature must be present" do
      request = build(:member_feature_request, feature: nil)

      refute request.valid?
      assert_equal "can't be blank or is invalid", request.errors[:feature].first
    end

    test "should not have duplicate requests for same requester, organization and feature" do
      first_request = create(:member_feature_request)
      another_request = build(:member_feature_request, requester: first_request.requester, request_entity: first_request.organization, feature: first_request.feature)

      refute another_request.valid?
      assert_equal "already requested", another_request.errors[:feature].first
      assert_equal 1, MemberFeatureRequest.where(requester: first_request.requester, request_entity: first_request.organization, feature: first_request.feature).count
    end

    context "requester_must_be_org_member_or_collaborator" do
      test "requester must be a request_entity member or a collaborator" do
        requester = build(:user)
        non_member_org = build(:organization)
        request = build(:member_feature_request, requester: requester, request_entity: non_member_org)

        refute request.valid?
        assert_equal "must be member of the organization or an outside collaborator", request.errors[:requester].first
      end

      test "validation does not run on update" do
        requester = create(:user)
        org = create(:organization, public_members: [requester])
        request = create(:member_feature_request, requester: requester, request_entity: org)

        assert request.valid?
        org.add_admin(requester)
        assert request.valid?
      end
    end

    context "requester_able_to_request_of_entity" do
      test "requester should not be admin when request is for non-enterprise-owned org and org_owner_raf FF is enabled" do
        org = create(:organization)
        request = build(:member_feature_request, requester: org.admin, request_entity: org)

        refute request.valid?
        assert_equal "must not be admin of the organization if the request is not for the enterprise", request.errors[:requester].first
      end

      test "requester should be admin when request is for enterprise-owned org and org_owner_raf FF is enabled" do
        request = build(:member_feature_request, requester: @org_user, request_entity: @request_entity, billing_entity: create(:business))

        refute request.valid?
        assert_equal "must be admin of the organization if the request is for the enterprise", request.errors[:requester].first
      end
    end

    context "copilot_seat_enabled_for_member" do
      test "requester already has a seat" do
        org = create(:organization, plan: :business)
        seat = create(:copilot_seat, organization: org)
        requester = seat.assigned_user
        org.add_member(requester)
        request = build(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: org, requester: requester)

        refute request.valid?
        assert_equal "already has a seat", request.errors[:requester].first
      end

      test "org has seats enabled for all members" do
        org = create(:organization, plan: :business)
        requester = create(:user)
        org.add_member(requester)
        Copilot::Organization.new(org).seat_management_allow_all!

        request = build(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: org, requester: requester)

        refute request.valid?
        assert_equal "already has a seat", request.errors[:requester].first
      end

      test "does not validate on update" do
        requester = create(:user)
        org = create(:organization, public_members: [requester])
        request = create(:member_feature_request, requester: requester, request_entity: org, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

        assert request.valid?
        create(:copilot_seat, assigned_user: requester, organization: org)
        assert request.valid?
      end
    end
  end

  context ".request_fulfilled?" do
    test "returns true if a request has been fulfilled" do
      request = create(:member_feature_request, requester: @org_user, request_entity: @request_entity, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :fulfilled)

      assert MemberFeatureRequest.request_fulfilled?(
        T.must(@org_user),
        T.must(@request_entity),
        MemberFeatureRequest::Feature::CopilotForBusiness
      )
    end

    test "returns true if a request has been fulfilled with billing_entity" do

      business = create(:business)
      enterprise_org = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(enterprise_org)
      request = create(:member_feature_request, requester: @admin, request_entity: enterprise_org, billing_entity: business, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :fulfilled)

      assert MemberFeatureRequest.request_fulfilled?(
        T.must(@admin),
        request.request_entity,
        MemberFeatureRequest::Feature::CopilotForBusiness,
        request.billing_entity
      )
    end

    test "returns false if a request has not been fulfilled" do
      request = create(:member_feature_request, requester: @org_user, request_entity: @request_entity, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :requested)

      refute MemberFeatureRequest.request_fulfilled?(
        T.must(@org_user),
        T.must(@request_entity),
        MemberFeatureRequest::Feature::CopilotForBusiness
      )
    end
  end

  context ".find_request" do
    test "returns nil if request is not found" do
      request = create(:member_feature_request, requester: @org_user, request_entity: @request_entity, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

      assert_nil MemberFeatureRequest.find_request(
        T.must(@org_user),
        T.must(@request_entity),
        MemberFeatureRequest::Feature::ProtectedBranches
      )
    end

    test "returns the request if it exists" do
      request = create(:member_feature_request, requester: @org_user, request_entity: @request_entity, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles)

      found_request = MemberFeatureRequest.find_request(
        T.must(@org_user),
        T.must(@request_entity),
        MemberFeatureRequest::Feature::CustomRepositoryRoles
      )

      assert_equal request, found_request
    end
  end

  context ".already_requested?" do
    test "returns false if a matching request has been fulfilled" do
      request = create(:member_feature_request, requester: @org_user, request_entity: @request_entity, feature: MemberFeatureRequest::Feature::ProtectedBranches, status: :fulfilled)

      refute MemberFeatureRequest.already_requested?(
        T.must(@org_user),
        T.must(@request_entity),
        MemberFeatureRequest::Feature::ProtectedBranches
      )
    end

    test "returns true if request already exists" do
      request = create(:member_feature_request, requester: @org_user, request_entity: @request_entity, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, status: :requested)

      assert MemberFeatureRequest.already_requested?(
        T.must(@org_user),
        T.must(@request_entity),
        MemberFeatureRequest::Feature::CustomRepositoryRoles
      )
    end

    test "returns true if a request already exists for the given requester, request_entity and feature" do
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      assert MemberFeatureRequest.already_requested?(request.requester, request.request_entity, MemberFeatureRequest::Feature::ProtectedBranches)
    end

    test "returns false if no request exists for the given requester, request_entity and feature" do
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)
      another_org = create(:organization)

      refute MemberFeatureRequest.already_requested?(another_org.admin, another_org, MemberFeatureRequest::Feature::ProtectedBranches)
    end
  end

  context ".can_request?" do
    test "returns true if user is not admin and feature is not present in org" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)

      assert MemberFeatureRequest.can_request?(user, org, MemberFeatureRequest::Feature::CopilotForBusiness)
    end

    test "returns false if user is admin of request_entity and request_entity is not enterprise-owned" do
      user = create(:user)
      org = create(:organization, admin: user)

      refute MemberFeatureRequest.can_request?(user, org, MemberFeatureRequest::Feature::CopilotForBusiness)
    end

    test "returns false if org already has the feature" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)

      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)

      refute MemberFeatureRequest.can_request?(user, org, MemberFeatureRequest::Feature::CopilotForBusiness)
    end
  end

  context ".cancel_request!" do
    test "cancels the request for the given requester, request_entity and feature" do
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      MemberFeatureRequest.cancel_request!(request.requester, request.request_entity, MemberFeatureRequest::Feature::ProtectedBranches)

      refute MemberFeatureRequest.already_requested?(request.requester, request.request_entity, MemberFeatureRequest::Feature::ProtectedBranches)
    end

    test "emits an MemberFeatureRequestCancelled event" do
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      freeze_time do
        MemberFeatureRequest.cancel_request!(request.requester, request.request_entity, MemberFeatureRequest::Feature::ProtectedBranches)

        # Reload some of the objects because they come from db and db has no timezone info (results in failed time comparison).
        # If you want to see the funky behavior, wrap the test with `Timecop.travel(Time.at(1699172493))`
        message = {
          actor: Hydro::EntitySerializer.user(request.requester),
          organization: Hydro::EntitySerializer.organization(request.request_entity.reload),
          member_feature_request_id: request.id,
          feature: request.feature.to_s,
          cancelled_at: Time.zone.now,
        }

        assert_hydro_published(message, schema: "hydro.schemas.github.v1.MemberFeatureRequestCancelled")
        assert_hydro_messages(count: 1, schema: "hydro.schemas.github.v1.MemberFeatureRequestCancelled")
      end
    end

    test "raises ActiveRecord::RecordNotFound if no request exists for the given requester, request_entity and feature" do
      assert_raises(ActiveRecord::RecordNotFound) do
        MemberFeatureRequest.cancel_request!(build_stubbed(:user), build_stubbed(:organization), MemberFeatureRequest::Feature::ProtectedBranches)
      end
    end

    context "when the request is made by an org admin (enterprise-owned org)" do
      test "billing_entity is recorded as the owning business" do
        request_entity = create(:enterprise_linked_organization, admin: @admin)
        business       = request_entity.business
        admin_request  = create(
          :member_feature_request,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness,
          request_entity: request_entity,
          billing_entity: business,
          requester: @admin
        )
        non_admin_request = create(
          :member_feature_request,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness,
          request_entity: request_entity,
          requester: @org_user
        )

        MemberFeatureRequest.cancel_request!(admin_request.requester, admin_request.request_entity, MemberFeatureRequest::Feature::CopilotForBusiness, admin_request.billing_entity)

        refute MemberFeatureRequest.already_requested?(admin_request.requester, admin_request.request_entity, MemberFeatureRequest::Feature::CopilotForBusiness, admin_request.billing_entity)
        assert MemberFeatureRequest.already_requested?(non_admin_request.requester, non_admin_request.request_entity, MemberFeatureRequest::Feature::CopilotForBusiness)
      end
    end
  end

  context "requested_member_requests" do
    test "return requested requests only made by members (non-admin) when FF is enabled" do

      create(:member_feature_request, feature: MemberFeatureRequest::Feature::DraftPullRequests, status: :requested, request_entity: @request_entity, billing_entity: @request_entity, requester: @org_user)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :requested, request_entity: @request_entity, billing_entity: @request_entity, requester: @org_user)

      billing_entity = create(:business)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :requested, request_entity: @request_entity, billing_entity: billing_entity,  requester: @admin)

      assert_equal 2, MemberFeatureRequest.requested_member_requests(T.must(@request_entity)).count
    end

    test "return all requested requests made by members" do
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::DraftPullRequests, status: :requested, request_entity: @request_entity, billing_entity: @request_entity, requester: @org_user)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :requested, request_entity: @request_entity, billing_entity: @request_entity, requester: @org_user)

      other_request_entity = create(:organization)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :requested, request_entity: other_request_entity, billing_entity: @request_entity, requester: @org_user)

      assert_equal 2, MemberFeatureRequest.requested_member_requests(T.must(@request_entity)).count
    end
  end

  context ".total_for_feature" do
    test "returns a count of requests for the given feature for the given request_entity" do
      request_entity = create(:organization, plan: :free)
      requesters = create_list(:user, 2)
      requesters.each do |requester|
        request_entity.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester)
      end

      another_requester = create(:user)
      request_entity.add_member(another_requester)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: another_requester)

      another_org_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      assert_equal 3, MemberFeatureRequest.total_for_feature(request_entity, MemberFeatureRequest::Feature::ProtectedBranches)
    end

    test "returns 0 if the feature is included for the given request_entity" do
      request_entity = create(:organization, plan: :business)
      requester = create(:user)
      request_entity.add_member(requester)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: requester)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: request_entity, requester: requester)

      another_org_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      assert_equal 0, MemberFeatureRequest.total_for_feature(request_entity, MemberFeatureRequest::Feature::ProtectedBranches)
      assert_equal 1, MemberFeatureRequest.total_for_feature(request_entity, MemberFeatureRequest::Feature::CustomRepositoryRoles)
    end

    test "returns the count if the request is not fulfilled" do
      request_entity = create(:copilot_for_business_enabled_non_enterprise_organization)
      requester = create(:user)
      request_entity.add_member(requester)
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester, status: :requested)

      assert_changes(-> { MemberFeatureRequest.total_for_feature(request_entity, MemberFeatureRequest::Feature::CopilotForBusiness) }, from: 1, to: 0) do
        request.fulfilled!
      end
    end
  end

  context ".total_by_feature" do
    test "returns a hash of feature => count for the given request_entity" do
      request_entity = create(:organization, plan: :free)
      requesters = create_list(:user, 2)
      requesters.each do |requester|
        request_entity.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester)
      end

      another_org_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      assert_equal({ MemberFeatureRequest::Feature::ProtectedBranches => 2, MemberFeatureRequest::Feature::CopilotForBusiness => 2 }, MemberFeatureRequest.total_by_feature(request_entity))
    end

    test "does not returns a feature if it is not on request_entity plan" do
      request_entity = create(:organization, plan: :business)
      requester = create(:user)
      request_entity.add_member(requester)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: requester)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: request_entity, requester: requester)

      another_org_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      assert_equal({ MemberFeatureRequest::Feature::CustomRepositoryRoles => 1 }, MemberFeatureRequest.total_by_feature(request_entity))
    end

    test "returns a feature if the request is not fulfilled" do
      request_entity = create(:copilot_for_business_enabled_non_enterprise_organization)
      requester = create(:user)
      request_entity.add_member(requester)
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester, status: :requested)

      assert_changes(
        -> { MemberFeatureRequest.total_by_feature(request_entity) },
        from: { MemberFeatureRequest::Feature::CopilotForBusiness => 1 },
        to: {},
      ) do
        request.fulfilled!
      end
    end
  end

  context ".total_requested_by_feature_since" do
    test "returns all requests in a hash of feature => count for the given billing_entity if no date is sent" do

      admin_1 = create(:user)
      admin_2 = create(:user)
      org = create(:organization, admins: [admin_1, admin_2], login: "myorg")
      member = create(:user)
      business_owner = create(:user)
      enterprise_org_admin = create(:user)
      business = create(:business, owners: [business_owner])
      create(:enterprise_linked_organization, business: business, admin: enterprise_org_admin, login: "enterpriseorg")

      request_1 = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, requester: admin_1, request_entity: org, billing_entity: business)
      request_1 = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, requester: admin_2, request_entity: org, billing_entity: business)
      request_3 = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, requester: member, request_entity: org, billing_entity: org)

      assert_equal MemberFeatureRequest.total_requested_by_feature_since(business), { MemberFeatureRequest::Feature::CopilotForBusiness => 2 }
    end

    test "returns filtered by date requests in a hash of feature => count for the given billing_entity" do
      request_entity = create(:organization, plan: :free)
      requesters = create_list(:user, 2)
      requests = requesters.map do |requester|
        request_entity.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester)
      end

      travel_to(1.month.ago) do
        requesters.each do |requester|
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: requester)
        end
      end

      assert_equal MemberFeatureRequest.total_requested_by_feature_since(request_entity, 7.days.ago), { MemberFeatureRequest::Feature::CopilotForBusiness => 2 }
    end

    test "returns only requested requests" do
      request_entity = create(:organization, plan: :free)
      requesters = create_list(:user, 2)
      requests = requesters.map do |requester|
        request_entity.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester)
      end
      requests.sample.fulfilled!

      assert_equal MemberFeatureRequest.total_requested_by_feature_since(request_entity, 7.days.ago), { MemberFeatureRequest::Feature::CopilotForBusiness => 1 }
    end
  end

  context ".latest_member_feature_request" do
    test "returns nil when org does not have the specified request" do
      request_entity = create(:free_organization)
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      refute MemberFeatureRequest.latest_member_feature_request(request_entity)
    end

    test "returns the latest request when org has requests" do
      request_entity = create(:free_organization)
      old_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::ProtectedBranches)
      latest_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::ProtectedBranches, updated_at: old_request.updated_at + 1.day)

      assert_equal latest_request, MemberFeatureRequest.latest_member_feature_request(request_entity)
    end

    test "returns the old request when org has fulfilled the latest request" do
      request_entity = create(:free_organization)
      old_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::CopilotForBusiness)
      latest_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: old_request.updated_at + 1.day, status: :fulfilled)

      assert_equal old_request, MemberFeatureRequest.latest_member_feature_request(request_entity)
    end
  end

  context ".latest_members_by_feature_request" do
    test "returns empty array when org does not have the specified request" do
      request_entity = create(:free_organization)
      request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches)

      assert_equal [], MemberFeatureRequest.latest_members_by_feature_request(
        request_entity,
        MemberFeatureRequest::Feature::ProtectedBranches,
        1
      )
    end

    test "returns the latest request when org has multiple requests" do
      request_entity = create(:free_organization)
      old_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::ProtectedBranches)
      latest_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::ProtectedBranches, updated_at: old_request.updated_at + 1.day)

      assert_equal [latest_request.requester.name], MemberFeatureRequest.latest_members_by_feature_request(
        request_entity,
        MemberFeatureRequest::Feature::ProtectedBranches,
        1
      )
    end

    test "returns the old request when org has fulfilled the latest request" do
      request_entity = create(:free_organization)
      old_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::CopilotForBusiness)
      latest_request = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: old_request.updated_at + 1.day, status: :fulfilled)

      assert_equal [old_request.requester.name], MemberFeatureRequest.latest_members_by_feature_request(
        request_entity,
        MemberFeatureRequest::Feature::CopilotForBusiness,
        1
      )
    end

    test "returns the request from a specific feature" do
      request_entity = create(:free_organization)
      request_copilot = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::CopilotForBusiness)
      request_branches = create(:member_feature_request, request_entity:, feature: MemberFeatureRequest::Feature::ProtectedBranches, updated_at: request_copilot.updated_at + 1.day, status: :fulfilled)

      assert_equal [request_copilot.requester.name], MemberFeatureRequest.latest_members_by_feature_request(
        request_entity,
        MemberFeatureRequest::Feature::CopilotForBusiness,
        1
      )
    end
  end

  context ".total_members_requesting_features" do
    test "returns the total of unique members which requested the feature for the request_entity" do
      request_entity = create(:organization)
      requesters = create_list(:user, 2)
      requesters.each do |requester|
        request_entity.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: request_entity, requester: requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::Rulesets, request_entity: request_entity, requester: requester)
      end
      another_org_request = create(:member_feature_request)

      assert_equal 2, MemberFeatureRequest.total_members_requesting_features(request_entity)
    end

    test "do not consider features supported on request_entity plan" do
      request_entity = create(:organization, plan: :business)
      requester_on_my_plan = create(:user)
      requester_not_on_my_plan = create(:user)
      request_entity.add_member(requester_on_my_plan)
      request_entity.add_member(requester_not_on_my_plan)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: request_entity, requester: requester_on_my_plan)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: request_entity, requester: requester_not_on_my_plan)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester_not_on_my_plan)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::Rulesets, request_entity: request_entity, requester: requester_not_on_my_plan)

      another_org_request = create(:member_feature_request)

      assert_equal 1, MemberFeatureRequest.total_members_requesting_features(request_entity)
    end

    test "do not consider fulfilled feature requests" do
      request_entity = create(:organization, plan: :business)
      requester = create(:user)
      request_entity.add_member(requester)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester, status: :fulfilled)
      Copilot::Organization.new(request_entity).enable_copilot!

      another_org_request = create(:member_feature_request)

      assert_equal 0, MemberFeatureRequest.total_members_requesting_features(request_entity)
    end

    test "do consider pending feature requests" do
      request_entity = create(:organization, plan: :business)
      requester = create(:user)
      request_entity.add_member(requester)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: request_entity, requester: requester)
      Copilot::Organization.new(request_entity).enable_copilot!

      another_org_request = create(:member_feature_request)

      assert_equal 1, MemberFeatureRequest.total_members_requesting_features(request_entity)
    end
  end

  test "deletes requests when member is removed from request_entity" do
    request_entity = create(:organization)
    requester = create(:user)
    request_entity.add_member(requester)
    create(:member_feature_request, request_entity: request_entity, requester: requester, feature: MemberFeatureRequest::Feature::ProtectedBranches)
    create(:member_feature_request, request_entity: request_entity, requester: requester, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles)

    request_entity.remove_member!(requester)

    assert_empty MemberFeatureRequest.where(requester: requester, request_entity: request_entity)
  end

  test "deletes all requests when request_entity is deleted" do
    request_entity = create(:organization)

    requester = create(:user)
    request_entity.add_member(requester)
    create(:member_feature_request, request_entity: request_entity, requester: requester, feature: MemberFeatureRequest::Feature::ProtectedBranches)

    request_entity.destroy

    assert_empty MemberFeatureRequest.where(request_entity: request_entity)
  end

  test "deletes all requests when requester is deleted" do
    first_request_entity = create(:organization)
    second_request_entity = create(:organization)

    requester = create(:user)
    first_request_entity.add_member(requester)
    second_request_entity.add_member(requester)
    create(:member_feature_request, request_entity: first_request_entity, requester: requester, feature: MemberFeatureRequest::Feature::ProtectedBranches)
    create(:member_feature_request, request_entity: second_request_entity, requester: requester, feature: MemberFeatureRequest::Feature::ProtectedBranches)

    requester.destroy

    assert_empty MemberFeatureRequest.where(requester: requester)
  end

  context "#dismiss_request!" do
    test "dismiss_request! updates status and sets dismissed_by_id and dismissed_at" do
      request = create(:member_feature_request, request_entity: @request_entity, requester: @org_user, status: :requested)
      dismissed_at = Time.current
      assert request.requested?

      travel_to dismissed_at do
        request.dismiss_request!(actor: @admin)

        assert request.dismissed?
        assert_equal @admin, request.dismissed_by
        assert_in_delta dismissed_at, request.dismissed_at, 1
      end
    end
  end

  context "#send_dismissal_email!" do
    test "sends an email" do
      request = create(:member_feature_request, status: :dismissed, request_entity: @request_entity, requester: @org_user)

      assert_enqueued_email_with(MemberFeatureRequestMailer, :notify_dismissal, args: request) do
        response = request.send_dismissal_email(actor: @admin)
        assert_equal true, response
      end
      hydro_data = {
        actor: Hydro::EntitySerializer.user(@admin),
        category: "member_feature_request",
        action: "send_dismissed_email",
        label: "request_id:#{request.id};actor_id:#{@admin&.id};requester_id:#{request.requester.id};owner_id:#{request.request_entity.id};owner_type:organization",
      }
      assert_hydro_published(hydro_data, schema: "github.analytics.v0.Event")
    end

    test "does not send an email if the request is not dismissed" do
      request = create(:member_feature_request, status: :requested, request_entity: @request_entity, requester: @org_user)

      assert_no_enqueued_emails do
        response = request.send_dismissal_email(actor: @admin)
        refute response
      end
    end
  end

  context ".sorted_organizations_by_features" do
    test "sorts by admin feature requests count" do

      business = create(:business)

      org_without_requests = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(org_without_requests)

      enterprise_org_with_admin_request = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(enterprise_org_with_admin_request)
      create(:member_feature_request, requester: @admin, request_entity: enterprise_org_with_admin_request,
        billing_entity: business, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

      sorted_organizations = MemberFeatureRequest.sorted_organizations_by_features(
        organizations: business.organizations,
        admin_feature_requests: MemberFeatureRequest.where(billing_entity: business),
        member_feature_requests: MemberFeatureRequest.where(billing_entity: business.organizations.pluck(:id))
      )

      assert_equal [enterprise_org_with_admin_request, org_without_requests], sorted_organizations
    end

    test "sorts by admin and member feature requests count" do

      business = create(:business)

      org_without_requests = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(org_without_requests)

      org_with_member_requests = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(org_with_member_requests)
      create(:member_feature_request, request_entity: org_with_member_requests,
        billing_entity: org_with_member_requests, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

      enterprise_org_with_admin_request = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(enterprise_org_with_admin_request)
      create(:member_feature_request, requester: @admin, request_entity: enterprise_org_with_admin_request,
        billing_entity: business, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

      sorted_organizations = MemberFeatureRequest.sorted_organizations_by_features(
        organizations: business.organizations,
        admin_feature_requests: MemberFeatureRequest.where(billing_entity: business),
        member_feature_requests: MemberFeatureRequest.where(billing_entity: business.organizations.pluck(:id))
      )

      assert_equal [enterprise_org_with_admin_request, org_with_member_requests, org_without_requests], sorted_organizations
    end

    test "returns same input if there is no requests" do

      business = create(:business)

      org_without_requests1 = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(org_without_requests1)

      org_without_requests2 = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(org_without_requests2)

      sorted_organizations = MemberFeatureRequest.sorted_organizations_by_features(
        organizations: business.organizations,
        admin_feature_requests: MemberFeatureRequest.where(billing_entity: business),
        member_feature_requests: MemberFeatureRequest.where(billing_entity: business.organizations.pluck(:id))
      )

      assert_equal [org_without_requests1, org_without_requests2].sort, sorted_organizations.sort
    end
  end

  context ".feature_requests_count_by_organizations" do
    test "returns feature request count and grouped by organization" do

      business = create(:business)

      org_with_member_requests = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(org_with_member_requests)
      request1 = create(:member_feature_request, request_entity: org_with_member_requests,
        billing_entity: org_with_member_requests, feature: MemberFeatureRequest::Feature::CopilotForBusiness)
      request2 = create(:member_feature_request, request_entity: org_with_member_requests,
        billing_entity: org_with_member_requests, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

      enterprise_org_with_admin_request = create(:enterprise_linked_organization, business: business, admin: @admin)
      business.add_organization(enterprise_org_with_admin_request)
      business_request = create(:member_feature_request, requester: @admin, request_entity: enterprise_org_with_admin_request,
        billing_entity: business, feature: MemberFeatureRequest::Feature::CopilotForBusiness)

      expected_response = {
        requests_count: 2,
        organizations: {
          org_with_member_requests.id => { admins: 0, members: 2, requesters: [request2.requester, request1.requester] },
          enterprise_org_with_admin_request.id => { admins: 1, members: 0, requesters: [business_request.requester] }
        }
      }

      actual_response = MemberFeatureRequest.feature_requests_count_by_organizations(
        admin_feature_requests: MemberFeatureRequest.where(billing_entity: business),
        member_feature_requests: MemberFeatureRequest.where(billing_entity: business.organizations.pluck(:id))
      )

      assert_equal expected_response[:requests_count], actual_response[:requests_count]

      expected_response[:organizations].each do |org_id, data|
        assert_equal data[:admins], actual_response[:organizations][org_id][:admins]
        assert_equal data[:members], actual_response[:organizations][org_id][:members]
        assert_equal data[:requesters].sort, actual_response[:organizations][org_id][:requesters].sort
      end
    end
  end
end
