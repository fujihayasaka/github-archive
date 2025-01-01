# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::CustomerTest < GitHub::TestCase
  context "#id_for" do
    context "when the entity is a user" do
      test "returns nil as there won't be a customer" do
        user = create(:user)

        assert_nil Licensing::Customer.id_for(user)
      end
    end

    context "when the entity is an organization" do
      test "delegates to the organization's licensed_customer_id" do
        org = create(:enterprise_linked_organization)

        assert_equal org.licensed_customer_id, Licensing::Customer.id_for(org)
      end
    end

    context "when the entity is a team" do
      test "delegates to the team's licensed_customer_id" do
        team = create(:team, organization: create(:enterprise_linked_organization))

        assert_equal team.licensed_customer_id, Licensing::Customer.id_for(team)
      end
    end

    context "when the entity is a repository" do
      test "returns the business customer_id when the repo is owned by a business" do
        repo = create(:repository, :enterprise_linked_org_owned)

        assert_equal repo.organization.business.customer_id, Licensing::Customer.id_for(repo)
      end

      test "returns the org's customer id when repo is owned by a paying org" do
        repo = create(:repository, owner: create(:organization, :with_azure_subscription))

        assert_equal repo.organization.customer.id, Licensing::Customer.id_for(repo)
      end

      test "returns nil when the repo owner is a standalone user" do
        repo = create(:repository, owner: create(:credit_card_user))

        refute Licensing::Customer.id_for(repo)
      end

      test "returns nil when the repo is owned by a standalone org without an associated customer" do
        repo = create(:repository, owner: create(:free_organization))

        refute Licensing::Customer.id_for(repo)
      end

      test "returns nil when the repo is owned by a user without an associated customer" do
        repo = create(:repository)

        refute Licensing::Customer.id_for(repo)
      end
    end
  end
end
