# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class BusinessResolverTest < GitHub::TestCase
    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @biz = create(:global_business)
    end

    context ".resolve_for" do
      context "entity is a repository" do
        context "owner is an organization" do
          test "it returns the business that contains the owner" do
            org = create :organization, business: @biz
            repo = create :repository, owner: org

            assert_equal @biz, BusinessResolver.resolve_for(repo)
          end

          context "not contained in a business", skip_enterprise: true do
            test "it returns nil" do
              biz_plus_org = create :business_plus_organization, skip_enterprise_managed_organization: true
              biz_plus_org_repo = create :repository, owner: biz_plus_org

              free_org = create :free_organization, skip_enterprise_managed_organization: true
              free_org_repo = create :repository, owner: free_org

              assert_nil BusinessResolver.resolve_for(biz_plus_org_repo)
              assert_nil BusinessResolver.resolve_for(free_org_repo)
            end
          end
        end

        context "owner is a user" do
          context "in dotcom", skip_enterprise: true do
            if TestEnv.test_with_all_emus?
              context "enterprise managed" do
                test "it returns the business that manages the user" do
                  user = create :user
                  repo = create :repository, owner: user, force_user_owned: true

                  assert_equal user.enterprise_managed_business, BusinessResolver.resolve_for(repo)
                end
              end
            end

            context "not enterprise managed", skip_with_all_emus: true do
              test "it returns nil" do
                user = create :user
                repo = create :repository, owner: user, force_user_owned: true

                assert_nil BusinessResolver.resolve_for(repo)
              end
            end
          end

          context "in GHES", enterprise_only: true do
            test "it returns the global business" do
              user = create :user
              repo = create :repository, owner: user, force_user_owned: true

              assert_equal GitHub.global_business, BusinessResolver.resolve_for(repo)
            end
          end
        end
      end

      context "entity is an organization" do
        test "it returns the business that contains the entity" do
          org = create :organization, business: @biz
          assert_equal @biz, BusinessResolver.resolve_for(org)
        end

        context "not contained in a business", skip_enterprise: true, skip_with_all_emus: true do
          test "it returns nil" do
            biz_plus_org = create :business_plus_organization
            free_org = create :free_organization

            assert_nil BusinessResolver.resolve_for(biz_plus_org)
            assert_nil BusinessResolver.resolve_for(free_org)
          end
        end
      end

      context "entity is a user" do
        context "in dotcom", skip_enterprise: true do
          if TestEnv.test_with_all_emus?
            context "enterprise managed" do
              test "it returns the business that manages the user" do
                user = create :user
                assert_equal user.enterprise_managed_business, BusinessResolver.resolve_for(user)
              end
            end
          end

          context "not enterprise managed", skip_with_all_emus: true do
            test "it returns nil" do
              user = create :user
              assert_nil BusinessResolver.resolve_for(user)
            end
          end
        end

        context "in GHES", enterprise_only: true do
          test "it returns the global business" do
            user = create :user
            assert_equal GitHub.global_business, BusinessResolver.resolve_for(user)
          end
        end
      end

      context "entity is a bot" do
        context "in dotcom", skip_enterprise: true do
          test "it raises" do
            user = create :bot
            assert_raises { BusinessResolver.resolve_for(user) }
          end
        end

        context "in GHES", enterprise_only: true do
          test "it returns the global business" do
            user = create :user
            assert_equal GitHub.global_business, BusinessResolver.resolve_for(user)
          end
        end
      end

      context "entity is a mannequin" do
        context "in dotcom", skip_enterprise: true do
          test "it raises" do
            user = create :mannequin
            assert_raises { BusinessResolver.resolve_for(user) }
          end
        end

        context "in GHES", enterprise_only: true do
          test "it returns the global business" do
            user = create :user
            assert_equal GitHub.global_business, BusinessResolver.resolve_for(user)
          end
        end
      end

      context "entity is an unacceptable type" do
        context "in dotcom", skip_enterprise: true do
          test "it raises" do
            assert_raises { BusinessResolver.resolve_for(T.cast(0, ::User)) }
          end
        end

        context "in GHES", enterprise_only: true do
          test "it returns the global business" do
            user = create :user
            assert_equal GitHub.global_business, BusinessResolver.resolve_for(user)
          end
        end
      end
    end
  end
end
