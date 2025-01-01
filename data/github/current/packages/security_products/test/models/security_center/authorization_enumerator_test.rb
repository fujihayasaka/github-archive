# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class AuthorizationEnumeratorTest < GitHub::TestCase
    extend T::Sig
    include ::SecurityCenter::TestFixtures

    setup do
      create_org_level_fixtures
      @wrong_org = create(:business_plus_organization, business: @biz, name: "wrong-org")

      SecurityFeatures.stubs(
        code_scanning_enabled_for_instance?: true,
        secret_scanning_enabled_for_instance?: true,
        dependabot_alerts_enabled_for_instance?: true,
      )
    end

    context "#allowed_repository_ids_by_feature" do
      context "owners" do
        test "returns nil" do
          assert_nil AuthorizationEnumerator.new(user: @owner, org: @org).allowed_repository_ids_by_feature
        end

        test "returns empty array for each feature for wrong org" do
          allowed_by_feature = AuthorizationEnumerator.new(user: @owner, org: @wrong_org).allowed_repository_ids_by_feature

          refute_nil allowed_by_feature
          refute_empty allowed_by_feature
          assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature&.keys
          allowed_by_feature&.each { |_, repo_ids| assert_empty repo_ids }
        end
      end

      context "security managers" do
        test "returns nil" do
          assert_nil AuthorizationEnumerator.new(user: @security_manager, org: @org).allowed_repository_ids_by_feature
        end

        test "returns empty array for each feature for wrong org" do
          allowed_by_feature = AuthorizationEnumerator.new(user: @security_manager, org: @wrong_org).allowed_repository_ids_by_feature

          refute_nil allowed_by_feature
          refute_empty allowed_by_feature
          assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature&.keys
          allowed_by_feature&.each { |_, repo_ids| assert_empty repo_ids }
        end
      end

      context "members" do
        test "returns repos where the user has access to those features" do
          allowed_by_feature = AuthorizationEnumerator.new(user: @member, org: @org).allowed_repository_ids_by_feature
          refute_nil allowed_by_feature
          refute_empty allowed_by_feature
          assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature&.keys
          allowed_by_feature&.each { |_, repo_ids| assert_empty repo_ids }

          allowed_by_feature = AuthorizationEnumerator.new(user: @repo_admin, org: @org).allowed_repository_ids_by_feature
          refute_nil allowed_by_feature
          refute_empty allowed_by_feature
          assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature&.keys
          allowed_by_feature&.each { |_, repo_ids| assert_same_elements [@private_repo.id], repo_ids }

          allowed_by_feature = AuthorizationEnumerator.new(user: @another_member, org: @org).allowed_repository_ids_by_feature
          refute_nil allowed_by_feature
          refute_empty allowed_by_feature
          assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature&.keys
          assert_same_elements [@private_repo.id, @another_repo.id], allowed_by_feature&.dig(:dependabot_alerts)
          assert_same_elements [@private_repo.id, @another_repo.id], allowed_by_feature&.dig(:code_scanning)
          assert_same_elements [@another_repo.id], allowed_by_feature&.dig(:secret_scanning)
        end

        test "returns empty array for each feature for wrong org" do
          [@member, @repo_admin, @another_member].each do |user|
            allowed_by_feature = AuthorizationEnumerator.new(user:, org: @wrong_org).allowed_repository_ids_by_feature

            refute_nil allowed_by_feature
            refute_empty allowed_by_feature
            allowed_by_feature&.each { |_, repo_ids| assert_empty repo_ids }
          end
        end
      end
    end

    context "#allowed_repository_ids_for_organization_member" do
      test "returns repos where the user has access to those features" do
        allowed_by_feature = AuthorizationEnumerator.new(user: @member, org: @org).allowed_repository_ids_by_feature_for_organization_member
        refute_nil allowed_by_feature
        refute_empty allowed_by_feature
        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys
        allowed_by_feature.each do |_, (repo_ids, limit_exceeded)|
          assert_empty repo_ids
          refute limit_exceeded
        end

        allowed_by_feature = AuthorizationEnumerator.new(user: @repo_admin, org: @org).allowed_repository_ids_by_feature_for_organization_member
        refute_nil allowed_by_feature
        refute_empty allowed_by_feature
        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys
        allowed_by_feature.each do |_, (repo_ids, limit_exceeded)|
          assert_same_elements [@private_repo.id], repo_ids
          refute limit_exceeded
        end

        allowed_by_feature = AuthorizationEnumerator.new(user: @another_member, org: @org).allowed_repository_ids_by_feature_for_organization_member
        refute_nil allowed_by_feature
        refute_empty allowed_by_feature

        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys

        assert_same_elements [@private_repo.id, @another_repo.id], allowed_by_feature.dig("dependabot_alerts", 0)
        refute allowed_by_feature.dig("dependabot_alerts", 1)

        assert_same_elements [@private_repo.id, @another_repo.id], allowed_by_feature.dig("code_scanning", 0)
        refute allowed_by_feature.dig("code_scanning", 1)

        assert_same_elements [@another_repo.id], allowed_by_feature.dig("secret_scanning", 0)
        refute allowed_by_feature.dig("secret_scanning", 1)
      end

      test "returns limited number of repos for each feature" do
        user = create(:user)
        @org.add_member(user)

        @private_repo.add_member(user, action: :admin)
        @another_repo.add_member(user, action: :admin)

        # Limit greater than number of repos user has permissions for
        ::SecurityCenter::AuthorizationEnumerator.stubs(:repo_limit_for_org_members).returns(3)
        allowed_by_feature = AuthorizationEnumerator.new(user:, org: @org).allowed_repository_ids_by_feature_for_organization_member

        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys
        allowed_by_feature.each do |_, (repo_ids, limit_exceeded)|
          assert_same_elements [@another_repo.id, @private_repo.id], repo_ids
          refute limit_exceeded
        end

        # Limit less than number of repos user has permissions for
        ::SecurityCenter::AuthorizationEnumerator.stubs(:repo_limit_for_org_members).returns(1)
        allowed_by_feature = AuthorizationEnumerator.new(user:, org: @org).allowed_repository_ids_by_feature_for_organization_member

        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys
        allowed_by_feature.each do |_, (repo_ids, limit_exceeded)|
          assert_same_elements [@another_repo.id], repo_ids
          assert limit_exceeded
        end
      end

      test "returns limited number of repos for each feature preferring most recently updated/pushed repos first" do
        user = create(:user)
        @org.add_member(user)

        @private_repo.add_member(user, action: :admin)
        @another_repo.add_member(user, action: :admin)

        earlier = Time.now.utc - 1.day
        later = Time.now.utc + 1.day

        RepositorySecurityCenterConfig.find_by(repository: @private_repo)&.update!(last_push: later)
        RepositorySecurityCenterConfig.find_by(repository: @another_repo)&.update!(last_push: earlier)
        ::SecurityCenter::AuthorizationEnumerator.stubs(:repo_limit_for_org_members).returns(1)
        allowed_by_feature = AuthorizationEnumerator.new(user:, org: @org).allowed_repository_ids_by_feature_for_organization_member

        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys
        allowed_by_feature.each do |_, (repo_ids, limit_exceeded)|
          assert_same_elements [@private_repo.id], repo_ids
          assert limit_exceeded
        end

        RepositorySecurityCenterConfig.find_by(repository: @private_repo)&.update!(last_push: earlier)
        RepositorySecurityCenterConfig.find_by(repository: @another_repo)&.update!(last_push: later)
        ::SecurityCenter::AuthorizationEnumerator.stubs(:repo_limit_for_org_members).returns(1)
        allowed_by_feature = AuthorizationEnumerator.new(user:, org: @org).allowed_repository_ids_by_feature_for_organization_member

        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys
        allowed_by_feature.each do |_, (repo_ids, limit_exceeded)|
          assert_same_elements [@another_repo.id], repo_ids
          assert limit_exceeded
        end
      end

      test "returns full permissions for repos even when limited" do
        user = create(:user)
        @org.add_member(user)

        @private_repo.add_member(user, action: :write) # Only code scanning and Dependabot alerts are available for write access.
        @another_repo.add_member(user, action: :admin) # All features are available for admin access.

        earlier = Time.now.utc - 1.day
        later = Time.now.utc + 1.day

        # Ensure we prefer private repo for the limit.
        # This means we'll choose private repo for code scanning and Dependabot alerts, and another repo for secret scanning.
        RepositorySecurityCenterConfig.find_by(repository: @private_repo)&.update!(last_push: later)
        RepositorySecurityCenterConfig.find_by(repository: @another_repo)&.update!(last_push: earlier)

        # Limit to a single repo per FGP/feature
        ::SecurityCenter::AuthorizationEnumerator.stubs(:repo_limit_for_org_members).returns(1)
        allowed_by_feature = AuthorizationEnumerator.new(user:, org: @org).allowed_repository_ids_by_feature_for_organization_member

        assert_same_elements %w[dependabot_alerts code_scanning secret_scanning], allowed_by_feature.keys

        # Despite repo limit, another repo is included because
        # it was chosen for secret scanning, and the user has more permissions on that repo than just secret scanning.
        assert_same_elements [@private_repo.id, @another_repo.id], allowed_by_feature.dig("dependabot_alerts", 0)
        assert allowed_by_feature.dig("dependabot_alerts", 1)

        # Despite repo limit, another repo is included because
        # it was chosen for secret scanning, and the user has more permissions on that repo than just secret scanning.
        assert_same_elements [@private_repo.id, @another_repo.id], allowed_by_feature.dig("code_scanning", 0)
        assert allowed_by_feature.dig("code_scanning", 1)

        # Secret scanning is not available on the private repo, so only another repo is included.
        assert_same_elements [@another_repo.id], allowed_by_feature.dig("secret_scanning", 0)
        refute allowed_by_feature.dig("secret_scanning", 1)
      end

      context "cached result" do
        test "is stored by function call" do
          with_cache_enabled do
            Timecop.freeze do
              allowed_by_feature = AuthorizationEnumerator.new(user: @member, org: @org).allowed_repository_ids_by_feature_for_organization_member
              refute_nil allowed_by_feature
              refute_empty allowed_by_feature

              cached_result = GitHub.cache.fetch("#{T.must(AuthorizationEnumerator.name).underscore}:allowed_repository_ids_by_feature_for_organization_member:#{@org.id}:#{@member.id}")
              assert_equal allowed_by_feature, cached_result
            end
          end
        end
      end
    end
  end
end
