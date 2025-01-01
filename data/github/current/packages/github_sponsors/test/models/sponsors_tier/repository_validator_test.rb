# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsTierRepositoryValidatorTest < GitHub::TestCase
  context "#errors" do
    test "returns no errors if repo is private, owned by an organization the user belongs to, is adminable by the sponsorable, and its sponsorable is a user" do
      sponsorable = create(:user)
      organization = create(:organization)
      organization.add_member(sponsorable)
      repository = create(:private_repository, owner: organization)
      repository.add_member(sponsorable, action: :admin)

      validator = create_validator(repository: repository, sponsorable: sponsorable)

      assert_empty validator.errors
    end

    test "returns no errors if repo is private, its sponsorable is an organization, and the repo owner is the sponsorable organization" do
      sponsorable_org = create(:organization)
      repository = create(:private_repository, owner: sponsorable_org)

      validator = create_validator(repository: repository, sponsorable: sponsorable_org)

      assert_empty validator.errors
    end

    test "returns an error if the repository is public" do
      sponsorable_org = create(:organization, :sponsorable)
      public_repository = create(:repository, owner: sponsorable_org)

      validator = create_validator(repository: public_repository, sponsorable: sponsorable_org)

      assert_equal validator.errors, ["must be private"]
    end

    test "returns an error if the repository is not adminable by the sponsorable" do
      sponsorable = create(:user)
      organization = create(:organization)
      repository = create(:private_repository, owner: organization)

      validator = create_validator(repository: repository, sponsorable: sponsorable)

      assert_equal validator.errors, ["#{sponsorable} must be an admin of the selected repository"]
    end

    test "returns an error if the repository's sponsorable is not the repo owner" do
      sponsorable_org = create(:organization)
      different_owner = create(:organization)
      repository = create(:private_repository, owner: different_owner)

      validator = create_validator(repository: repository, sponsorable: sponsorable_org)

      assert_equal validator.errors, ["owner must be #{sponsorable_org.login}"]
    end

    test "returns an error if the repository is not owned by an organization" do
      sponsorable = create(:user)
      repository = create(:private_repository, owner: sponsorable)

      validator = create_validator(repository: repository, sponsorable: sponsorable)

      assert_equal validator.errors, ["must be owned by an organization"]
    end

    test "returns an error if the repository is enterprise-managed", skip_enterprise: true do
      sponsorable = create(:emu, :sponsorable, login: "emuSponsorable")
      enterprise = sponsorable.enterprise_managed_business
      organization = create(:organization, business: enterprise)
      organization.add_admin(sponsorable)
      repository = create(:private_repository, owner: organization)

      validator = create_validator(repository: repository, sponsorable: sponsorable)

      assert_equal validator.errors, ["must not be enterprise-managed"]
    end
  end

  def create_validator(repository:, sponsorable:)
    SponsorsTier::RepositoryValidator.new(repository: repository, sponsorable: sponsorable)
  end
end
