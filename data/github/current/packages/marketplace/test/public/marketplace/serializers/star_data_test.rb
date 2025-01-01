# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Serializers::StarDataTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @current_user = create(:user)
  end

  context "#call" do
    context "starredByCurrentUser" do
      context "when there is not a current user" do
        context "when logged in is false" do
          test "returns false" do
            star_data = Marketplace::Serializers::StarData.new(
              logged_in: false,
              current_user: nil,
              repository: @repo,
              emu_contribution_blocked: false
            )

            assert_equal false, star_data.call[:starredByCurrentUser]
          end
        end

        context "when logged in is true" do
          test "returns false" do
            star_data = Marketplace::Serializers::StarData.new(
              logged_in: true,
              current_user: nil,
              repository: @repo,
              emu_contribution_blocked: false
            )

            assert_equal false, star_data.call[:starredByCurrentUser]
          end
        end
      end

      context "when there is a current user" do
        context "when logged in is false" do
          test "returns false" do
            star_data = Marketplace::Serializers::StarData.new(
              logged_in: false,
              current_user: @current_user,
              repository: @repo,
              emu_contribution_blocked: false
            )

            assert_equal false, star_data.call[:starredByCurrentUser]
          end
        end

        context "when logged in is true" do
          context "when the current user has starred the repository" do
            test "returns true" do
              Stars.domain.star_repository(repository: @repo, user: @current_user)

              star_data = Marketplace::Serializers::StarData.new(
                logged_in: true,
                current_user: @current_user,
                repository: @repo,
                emu_contribution_blocked: false
              )

              assert_equal true, star_data.call[:starredByCurrentUser]
            end
          end

          context "when the current user has not starred the repository" do
            test "returns false" do
              star_data = Marketplace::Serializers::StarData.new(
                logged_in: true,
                current_user: @current_user,
                repository: @repo,
                emu_contribution_blocked: false
              )

              assert_equal false, star_data.call[:starredByCurrentUser]
            end
          end
        end
      end
    end

    context "currentUserAbleToStar" do
      context "when there is not a current user" do
        context "when logged in is false" do
          test "returns false" do
            star_data = Marketplace::Serializers::StarData.new(
              logged_in: false,
              current_user: nil,
              repository: @repo,
              emu_contribution_blocked: false
            )

            assert_equal false, star_data.call[:currentUserAbleToStar]
          end
        end

        context "when logged in is true" do
          test "returns false" do
            star_data = Marketplace::Serializers::StarData.new(
              logged_in: true,
              current_user: nil,
              repository: @repo,
              emu_contribution_blocked: false
            )

            assert_equal false, star_data.call[:currentUserAbleToStar]
          end
        end
      end

      context "when there is a current user" do
        context "when logged in is false" do
          test "returns false" do
            star_data = Marketplace::Serializers::StarData.new(
              logged_in: false,
              current_user: @current_user,
              repository: @repo,
              emu_contribution_blocked: false
            )

            assert_equal false, star_data.call[:currentUserAbleToStar]
          end
        end

        context "when logged in is true" do
          context "when the current user is an enterprise manager user", skip_enterprise: true do
            context "when emu_contribution_blocked is true" do
              test "returns false" do
                @current_user = user = create(:emu)

                star_data = Marketplace::Serializers::StarData.new(
                  logged_in: true,
                  current_user: @current_user,
                  repository: @repo,
                  emu_contribution_blocked: true
                )

                assert_equal false, star_data.call[:currentUserAbleToStar]
              end
            end

            context "when emu_contribution_blocked is false", skip_enterprise: true do
              test "returns true" do
                @current_user = create(:emu)

                star_data = Marketplace::Serializers::StarData.new(
                  logged_in: true,
                  current_user: @current_user,
                  repository: @repo,
                  emu_contribution_blocked: false
                )

                assert_equal true, star_data.call[:currentUserAbleToStar]
              end
            end
          end

          context "when the current user is not an enterprise manager user" do
            context "when emu_contribution_blocked is true" do
              test "returns true" do
                star_data = Marketplace::Serializers::StarData.new(
                  logged_in: true,
                  current_user: @current_user,
                  repository: @repo,
                  emu_contribution_blocked: true
                )

                assert_equal true, star_data.call[:currentUserAbleToStar]
              end
            end

            context "when emu_contribution_blocked is false" do
              test "returns true" do
                star_data = Marketplace::Serializers::StarData.new(
                  logged_in: true,
                  current_user: @current_user,
                  repository: @repo,
                  emu_contribution_blocked: false
                )

                assert_equal true, star_data.call[:currentUserAbleToStar]
              end
            end
          end
        end
      end
    end

    context "currentUserEnterpriseName" do
      test "returns the current user's enterprise name", skip_enterprise: true do
        @current_user = create(:emu)

        star_data = Marketplace::Serializers::StarData.new(
          logged_in: true,
          current_user: @current_user,
          repository: @repo,
          emu_contribution_blocked: false
        )

        assert_equal @current_user.enterprise_managed_business.name, star_data.call[:currentUserEnterpriseName]
      end
    end
  end
end
