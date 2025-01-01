# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationPeopleSearchTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @admin = create :user, login: "org-admin"
    @org = create(:organization, admin: @admin)
    @member = create(:user, login: "member")
    @member.emails.each(&:verify!)
    @org.add_member(@member)
    @stranger = create(:user, login: "stranger")
  end

  context "#call" do
    test "return all members when searching an org" do
      res = subject.new(query: query, users: User).call
      assert_same_elements [@admin, @member], res
    end

    test "return matching members when searching an org" do
      q = query(query: @admin.login[0..4])
      res = subject.new(query: q, users: User).call
      assert_same_elements [@admin], res
    end

    test "filters users with linked external identities" do
      provider = create :organization_saml_provider, organization: @org

      ai = create :external_identity, user: @admin, provider: provider
      ai.update! user: nil

      unlinked = create :user, login: "unlinked-member"
      @org.add_member unlinked
      ui = create :external_identity, user: unlinked, provider: provider
      ui.update! user: nil

      create :external_identity, user: @member, provider: provider

      linked = create :user, login: "linked-member"
      @org.add_member linked
      create :external_identity, user: linked, provider: provider

      q = query(query: "sso:linked")
      filtered = Organization::People::Filter.new(query: q).call
      res = subject.new(query: q, users: filtered).call

      assert_same_elements [@member, linked], res
    end

    test "filters users with unlinked external identities" do
      provider = create :organization_saml_provider, organization: @org

      unlinked = create :user, login: "unlinked-member"
      @org.add_member unlinked
      ui = create :external_identity, user: unlinked, provider: provider
      ui.update! user: nil

      create :external_identity, user: @member, provider: provider

      linked = create :user, login: "linked-member"
      @org.add_member linked
      create :external_identity, user: linked, provider: provider

      q = query(query: "sso:unlinked")
      filtered = Organization::People::Filter.new(query: q).call
      res = subject.new(query: q, users: filtered).call

      assert_same_elements [@admin, unlinked], res
    end

    test "filters users with unlinked external identities when they may have other linked external identities" do
      create :external_identity, user: @admin
      provider = create :organization_saml_provider, organization: @org

      unlinked = create :user, login: "unlinked-member"
      @org.add_member unlinked
      ui = create :external_identity, user: unlinked, provider: provider
      ui.update! user: nil
      create :external_identity, user: unlinked

      create :external_identity, user: @member, provider: provider

      linked = create :user, login: "linked-member"
      @org.add_member linked
      create :external_identity, user: linked, provider: provider

      q = query(query: "sso:unlinked")
      filtered = Organization::People::Filter.new(query: q).call
      res = subject.new(query: q, users: filtered).call

      assert_same_elements [@admin, unlinked], res
    end

    test "ignores sso:linked query when no external identity provider exists" do
      q = query(query: "sso:linked")
      filtered = Organization::People::Filter.new(query: q).call
      res = subject.new(query: q, users: filtered).call

      assert_same_elements [@admin, @member], res
    end

    test "ignores sso:unlinked query when no external identity provider exists" do
      q = query(query: "sso:unlinked")
      filtered = Organization::People::Filter.new(query: q).call
      res = subject.new(query: q, users: filtered).call

      assert_same_elements [@admin, @member], res
    end

    test "filters guest collaborators" do
      guest_collaborator = create(:emu, :guest_collaborator)
      emu_business = guest_collaborator.enterprise_managed_business

      emu_user = create(:emu, business: emu_business)
      emu_org = create :organization, business: emu_business
      emu_org.add_member(guest_collaborator)
      emu_org.add_member(emu_user)
      q = query(query: "role:guest_collaborator", organization: emu_org, current_user: emu_user)
      filtered = Organization::People::Filter.new(query: q).call
      res = subject.new(query: q, users: filtered).call

      assert_same_elements [guest_collaborator], res

    end unless GitHub.single_business_environment?

    test "calls visible_user_ids_for with :guest_collaborator type" do
      guest_collaborator = create(:emu, :guest_collaborator)
      emu_business = guest_collaborator.enterprise_managed_business

      emu_user = create(:emu, business: emu_business)
      emu_org = create :organization, business: emu_business
      emu_org.add_member(guest_collaborator)
      emu_org.add_member(emu_user)

      emu_org.expects(:visible_user_ids_for).with(emu_user, type: :guest_collaborator, limit: Organization::MEGA_ORG_MEMBER_THRESHOLD, include_indirect_abilities: true).returns([guest_collaborator.id])

      q = query(query: "role:guest_collaborator", organization: emu_org, current_user: emu_user)
      filtered = Organization::People::Filter.new(query: q).call
      subject.new(query: q, users: filtered).call
    end unless GitHub.single_business_environment?
  end

  private

  def subject
    Organization::People::Search
  end

  def query(**opts)
    query = opts.fetch(:query, "")
    organization = opts.fetch(:organization, @org)
    current_user = opts.fetch(:current_user, @admin)
    role = opts[:role]

    Organization::People::Query.new(
      query: query,
      organization: organization,
      current_user: current_user,
      role: role,
    )
  end
end
