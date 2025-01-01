# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class OwnerTest < GitHub::TestCase
        fixtures do
          if GitHub.enterprise?
            @business_owner = create(:user, login: "test-biz-admin")
            @business = create(:business, owners: [@business_owner])
            @user = create(:user, business: @business, login: "test-user-apple")
            @org_admin = create(:user, business: @business, login: "test-org-admin")
          else
            @business = create(:business, :enterprise_managed)
            @business_owner = create(:emu, :owner, business: @business, login: "test-biz-admin")
            @user = create(:emu, business: @business, login: "test-user-apple")
            @org_admin = create(:emu, business: @business, login: "test-org-admin")
          end

          @org_1 = create(:organization, business: @business, login: "org-apple-1", admin: @org_admin)
          @org_2 = create(:organization, business: @business, login: "org-banana-2", admin: @org_admin)
          @org_3 = create(:organization, business: @business, login: "org-apple-3", admin: @org_admin)
          @org_4 = create(:organization, business: @business, login: "org-banana-4", admin: @org_admin)
        end

        setup do
          @business.mark_advanced_security_as_purchased_for_entity(actor: @business_owner)
        end

        context "when requested from business owner" do
          test "it returns suggestions for all authorized orgs and users" do
            suggestions = Owner.new(authorized_orgs: [@org_1], business: @business, user: @business_owner).suggestions

            expected_suggestions = [@org_1].map do |org|
              Suggestion.new(value: org.display_login, description: "Organization")
            end.concat([@business_owner, @org_admin, @user].map do |user|
              Suggestion.new(value: user.display_login, description: "User")
            end)

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns user suggestions when authorized_orgs is empty" do
            suggestions = Owner.new(authorized_orgs: [], business: @business, user: @business_owner).suggestions

            expected_suggestions = [@business_owner, @org_admin, @user].map do |user|
              Suggestion.new(value: user.display_login, description: "User")
            end

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns no suggestion if user owner is not supported" do
            if GitHub.enterprise?
              GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
            else
              @business.mark_advanced_security_as_not_purchased_for_entity(actor: @business_owner)
            end
            suggestions = Owner.new(authorized_orgs: [], business: @business, user: @business_owner).suggestions

            assert_same_elements([], suggestions)
          end
        end

        context "when requested from none business owner" do
          test "it returns suggestions for all authorized orgs" do
            suggestions = Owner.new(authorized_orgs: [@org_1], business: @business, user: @org_admin).suggestions

            expected_suggestions = [@org_1].map do |org|
              Suggestion.new(value: org.display_login, description: "Organization")
            end

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns no suggestion when authorized_orgs is empty" do
            suggestions = Owner.new(authorized_orgs: [], business: @business, user: @org_admin).suggestions

            assert_same_elements([], suggestions)
          end
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Owner.new(
              authorized_orgs: [@org_1, @org_2, @org_3, @org_4],
              selected_values: [@org_1.display_login, @org_3.display_login, @org_admin.display_login],
              business: @business,
              user: @business_owner
            ).suggestions

            expected_suggestions = [@org_2, @org_4].map do |org|
              Suggestion.new(value: org.display_login, description: "Organization")
            end.concat([@business_owner, @user].map do |user|
              Suggestion.new(value: user.display_login, description: "User")
            end)

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        context "when hint text is provided" do
          test "it returns suggestions matching the value" do
            suggestions = Owner.new(
              authorized_orgs: [@org_1, @org_2, @org_3, @org_4],
              value: "apple",
              business: @business,
              user: @business_owner
            ).suggestions

            expected_suggestions = [@org_1, @org_3].map do |org|
              Suggestion.new(value: org.display_login, description: "Organization")
            end.concat([
              Suggestion.new(value: @user.display_login, description: "User"),
            ])

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        test "it returns suggestions in ascending alphabetical order by name with org names first" do
          feature = ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          users = feature.list_enterprise_users_offset(offset_id: 0, per_page: 100).to_a

          suggestions = Owner.new(
            authorized_orgs: [@org_1, @org_2, @org_3, @org_4],
            business: @business,
            user: @business_owner
          ).suggestions

          expected_suggestions = [@org_1, @org_3, @org_2, @org_4].map do |org|
            Suggestion.new(value: org.display_login, description: "Organization")
          end.concat([@business_owner, @org_admin, @user].map do |user|
            Suggestion.new(value: user.display_login, description: "User")
          end)

          assert_equal(expected_suggestions, suggestions)
        end

        test "it limits the number of suggestions returned" do
          suggestions = Owner.new(
            authorized_orgs: [@org_1, @org_2, @org_3, @org_4],
            limit: 2,
            business: @business,
            user: @business_owner
          ).suggestions

          expected_suggestions = [@org_1, @org_3].map do |org|
            Suggestion.new(value: org.display_login, description: "Organization")
          end

          assert_equal(expected_suggestions, suggestions)
        end
      end
    end
  end
end
