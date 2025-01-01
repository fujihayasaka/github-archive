# typed: true
# frozen_string_literal: true

require "test_helper"

class ValidatePrebuildAccessTest < GitHub::TestCase
  include CodespacesPlanFixtures

  test "raises authorization error when repo organization does not have codespaces enabled" do
    org = create(:codespaces_organization, :disabled)
    repository = create(:private_repository, owner: org)

    args = {
      repository: repository, vscs_target: nil, vscs_target_url: nil
    }

    assert_raises Codespaces::ValidatePrebuildAccess::AuthorizationError do
      Codespaces::ValidatePrebuildAccess.call(**args)
    end
  end

  test "does not raise authorization error when repo organization does not have codespaces enabled required_enabled_org is false" do
    org = create(:codespaces_organization)
    repository = create(:private_repository, owner: org)

    Codespaces::OrgPolicy.stubs(:enabled_by_organization?).returns(false)

    args = {
      repository: repository, vscs_target: nil, vscs_target_url: nil, require_enabled_org: false
    }

    assert_nothing_raised do
      Codespaces::ValidatePrebuildAccess.call(**args)
    end
  end

  test "raises authorization error when vscs target url is set but the repository owner is not a codespaces developer" do
    repository = create(:repository)
    GitHub.flipper[:codespaces_developer].disable repository.owner

    args = {
      repository: repository, vscs_target: nil, vscs_target_url: "localhost:3000"
    }

    assert_raises Codespaces::ValidatePrebuildAccess::AuthorizationError do
      Codespaces::ValidatePrebuildAccess.call(**args)
    end
  end

  test "raises authorization error when vscs target is not production but the repository owner is not a codespaces developer" do
    repository = create(:repository)
    GitHub.flipper[:codespaces_developer].disable repository.owner

    args = {
      repository: repository, vscs_target: "local", vscs_target_url: nil
    }

    assert_raises Codespaces::ValidatePrebuildAccess::AuthorizationError do
      Codespaces::ValidatePrebuildAccess.call(**args)
    end
  end


  test "raises creation circuit breaker error the disable_codespace_creation feature flag is on" do
    repository = create(:repository)
    GitHub.flipper[:codespaces_developer].enable repository.owner
    GitHub.flipper[:disable_codespace_creation].enable repository.owner

    args = {
      repository: repository, vscs_target: nil, vscs_target_url: nil
    }

    assert_raises Codespaces::ValidatePrebuildAccess::CreationCircuitBreaker do
      Codespaces::ValidatePrebuildAccess.call(**args)
    end
  end

  test "does not raise error when vscs_target is :production and user is not a codespaces developer" do
    repository = create(:repository)

    args = {
      repository: repository, vscs_target: "production", vscs_target_url: nil
    }

    Codespaces::ValidatePrebuildAccess.call(**args)
  end

  test "does not raise error when vscs_target is nil and user is not a codespaces developer" do
    repository = create(:repository)

    args = {
      repository: repository, vscs_target: nil, vscs_target_url: nil
    }

    Codespaces::ValidatePrebuildAccess.call(**args)
  end

  test "does not raise error when vscs_target is production, vscs_target is empty strings, and user is not a codespaces developer" do
    repository = create(:repository)

    args = {
      repository: repository, vscs_target: "production", vscs_target_url: ""
    }

    Codespaces::ValidatePrebuildAccess.call(**args)
  end

  test "allows codespaces developers to set vscs_target that is not :production and a vscs_target_url" do
    repository = create(:repository)
    GitHub.flipper[:codespaces_developer].enable repository.owner

    args = {
      repository: repository, vscs_target: :local, vscs_target_url: "localhost:3000"
    }

    Codespaces::ValidatePrebuildAccess.call(**args)
  end

  test "does not raise error when an organization repository has codespace access" do
    org = create(:codespaces_organization)
    repository = create(:private_repository, owner: org)
    Codespaces::OrgPolicy.stubs(:enabled_by_organization?).returns(true)

    args = {
      repository: repository, vscs_target: nil, vscs_target_url: nil
    }

    Codespaces::ValidatePrebuildAccess.call(**args)
  end


end unless GitHub.enterprise?
