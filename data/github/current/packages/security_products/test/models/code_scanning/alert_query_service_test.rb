# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class AlertQueryServiceTest < GitHub::TestCase
    include ::SecurityCenter::TurboscanTestSetup

    fixtures do
      # Create organizations.
      @org_admin = create(:user)
      @user_session = create(:user_session, user: @org_admin)
      @org1 = create(:business_plus_organization, login: "Org1")
      @org1.add_admin(@org_admin)
      @org2 = create(:business_plus_organization, login: "Org2")
      @org2.add_admin(@org_admin)

      # Create repositories.
      @org1_public_repo = create(:repository, owner: @org1)
      create(:repository_security_center_config, repository: @org1_public_repo)
      @org1_private_repo = create(:private_repository, owner: @org1)
      create(:repository_security_center_config, repository: @org1_private_repo)
      @org1_private_repo2 = create(:private_repository, owner: @org1)
      create(:repository_security_center_config, repository: @org1_private_repo2)

      @org2_public_repo = create(:repository, owner: @org2)
      create(:repository_security_center_config, repository: @org2_public_repo)
      @org2_private_repo = create(:private_repository, owner: @org2)
      create(:repository_security_center_config, repository: @org2_private_repo)

      # Create businesses.
      @business = create(:global_business)
      @business.add_organization(@org1)
      @business.add_organization(@org2)

      # Create teams
      @org1_secret_team = create(:secret_team, organization: @org1).tap { |t| t.add_repository(@org1_private_repo, :admin) }
      @org1_secret_team2 = create(:secret_team, organization: @org1).tap { |t| t.add_repository(@org1_private_repo2, :admin) }
      @org1_public_team = create(:public_team, organization: @org1).tap { |t| t.add_repository(@org1_public_repo, :admin) }

      # Create topics
      @org1_private_repo_topic = create(:topic, name: "org1_private_repo_topic")
      create(:repository_topic, topic: @org1_private_repo_topic, state: :created, repository: @org1_private_repo)
      @org1_private_repo2_topic = create(:topic, name: "org1_private_repo2_topic")
      create(:repository_topic, topic: @org1_private_repo2_topic, state: :created, repository: @org1_private_repo2)
      @org1_public_repo_topic = create(:topic, name: "org1_public_repo_topic")
      create(:repository_topic, topic: @org1_public_repo_topic, state: :created, repository: @org1_public_repo)

      # Create repo with multiple topics
      @org1_repo_with_topics = create(:repository, owner: @org1).tap do |r|
        create(:repository_security_center_config, repository: r)
        create(:repository_topic, topic: @org1_private_repo_topic, state: :created, repository: r)
        create(:repository_topic, topic: @org1_private_repo2_topic, state: :created, repository: r)
        create(:repository_topic, topic: @org1_public_repo_topic, state: :created, repository: r)
      end
    end

    setup do
      @default_alerts_by_repo_args = @default_alerts_by_repo_args.merge({ owner_ids: [@org1.id] })
    end

    context ".for_business" do
      test "creates instance" do
        result = CodeScanning::AlertQueryService.for_business(
          user: @org_admin,
          user_session: @user_session,
          business: @business,
          organizations: @business.organizations
        )
        assert result.instance_of? CodeScanning::AlertQueryService
      end
    end

    context ".for_organization" do
      test "creates instance" do
        result = CodeScanning::AlertQueryService.for_organization(user: @org_admin, user_session: @user_session, organization: @org1)
        assert result.instance_of? CodeScanning::AlertQueryService
      end
    end

    context "#alerts_by_repo" do
      context "business-level" do
        context "no repos are selected" do
          test "passes no repo IDs to Turboscan" do
            GitHub::Turboscan
              .expects(:alerts_by_repo)
              .once
              .with(has_entries(@default_alerts_by_repo_args.merge(owner_ids: includes(@org1.id, @org2.id))))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::AlertsByRepoResponse.new({
                    open_count: 4,
                    resolved_count: 0,
                    results: [
                      Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result }),
                      Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result }),
                      Turboscan::Proto::RepoResult.new({ repository_id: @org2_public_repo.id, result: @default_turboscan_result }),
                      Turboscan::Proto::RepoResult.new({ repository_id: @org2_private_repo.id, result: @default_turboscan_result })
                    ]
                  })
                )
              )

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 4)
            assert_equal(4, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end
        end

        context "repos from authorized orgs are selected" do
          test "passes all selected repo IDs to Turboscan" do
            GitHub::Turboscan
              .expects(:alerts_by_repo)
              .once
              .with(has_entries(
                @default_alerts_by_repo_args.merge(
                  owner_ids: includes(@org1.id, @org2.id),
                  repository_ids: includes(@org1_public_repo.id, @org2_private_repo.id),
                )
              ))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::AlertsByRepoResponse.new({
                    open_count: 2,
                    resolved_count: 0,
                    results: [
                      Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result }),
                      Turboscan::Proto::RepoResult.new({ repository_id: @org2_private_repo.id, result: @default_turboscan_result })
                    ]
                  })
                )
              )

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "repo:#{@org1_public_repo.nwo},#{@org2_private_repo.nwo}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 2)
            assert_equal(2, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "caps number of repo IDs sent to Turboscan" do
            GitHub::Turboscan
              .expects(:alerts_by_repo)
              .once
              .with(has_entries(
                @default_alerts_by_repo_args.merge(
                  owner_ids: includes(@org1.id, @org2.id),
                  repository_ids: any_of([@org1_public_repo.id], [@org2_private_repo.id]),
                )
              ))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::AlertsByRepoResponse.new({
                    open_count: 1,
                    resolved_count: 0,
                    results: [
                      Turboscan::Proto::RepoResult.new({ repository_id: @org2_private_repo.id, result: @default_turboscan_result })
                    ]
                  })
                )
              )

            AlertQueryService::BusinessScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
              service = AlertQueryService.for_business(
                user: @org_admin,
                user_session: @user_session,
                business: @business,
                organizations: @business.organizations,
                query: "repo:#{@org1_public_repo.nwo},#{@org2_private_repo.nwo}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end
          end
        end

        context "repos from unauthorized orgs are selected" do
          test "passes only selected repo IDs from authorized orgs to Turboscan" do
            GitHub::Turboscan
              .expects(:alerts_by_repo)
              .once
              .with(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org2.id],
                  repository_ids: [@org2_private_repo.id]
                )
              )
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::AlertsByRepoResponse.new({
                    open_count: 0,
                    resolved_count: 1,
                    results: [Turboscan::Proto::RepoResult.new({ repository_id: @org2_private_repo.id, result: @default_turboscan_result })]
                  })
                )
              )

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations - [@org1],
              query: "repo:#{@org1_public_repo.nwo},#{@org2_private_repo.nwo}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 1)
            assert_equal(0, open_count)
            assert_equal(1, closed_count)
            refute(has_error)
          end
        end

        context "team filter" do
          test "single include" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                repository_ids: includes(@org1_private_repo.id),
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                ]
              })
            ))

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "team:#{@org1_secret_team.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 1)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "single exclude" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                excluded_repository_ids: [@org1_private_repo.id]
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result }),
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo2.id, result: @default_turboscan_result }),
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_repo_with_topics.id, result: @default_turboscan_result })
                ]
              })
            ))

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "-team:#{@org1_secret_team.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 3)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "single conflict" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "team:#{@org1_secret_team.name} -team:#{@org1_secret_team.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "conflict with include" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                repository_ids: [@org1_private_repo2.id]
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                ]
              })
            ))

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "team:#{@org1_secret_team.name},#{@org1_secret_team2.name} -team:#{@org1_secret_team.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 1)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "conflict with exclude" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "team:#{@org1_secret_team.name} -team:#{@org1_secret_team.name},#{@org1_secret_team2.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "invalid value" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "team:woof"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "user permissions to see team" do
            member = create(:user)
            @org1.add_member(member)
            query = "team:#{@org1_secret_team.name}"
            GitHub::Turboscan.expects(:alerts_by_repo).never
            service = AlertQueryService.for_business(
              user: member,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: query
            )
            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)

            query = "team:#{@org1_public_team.name}"
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                repository_ids: [@org1_public_repo.id]
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })
                ]
              })
            ))
            service = AlertQueryService.for_business(
              user: member,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: query
            )
            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 1)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "caps number of repo IDs sent" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                repository_ids: any_of([@org1_private_repo.id], [@org1_private_repo2.id]),
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                ]
              })
            ))

            AlertQueryService::BusinessScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
              service = AlertQueryService.for_business(
                user: @org_admin,
                user_session: @user_session,
                business: @business,
                organizations: [@org1, @org2],
                query: "team:#{@org1_secret_team.name},#{@org1_secret_team2.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end
          end
        end

        context "topic filter" do
          test "single include" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                repository_ids: includes(@org1_private_repo.id, @org1_repo_with_topics.id)
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                ]
              })
            ))

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "topic:#{@org1_private_repo_topic.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 1)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "single exclude" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                excluded_repository_ids: [@org1_private_repo.id, @org1_repo_with_topics.id]
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result }),
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo2.id, result: @default_turboscan_result })
                ]
              })
            ))

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "-topic:#{@org1_private_repo_topic.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 2)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "single conflict" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "topic:#{@org1_private_repo_topic.name} -topic:#{@org1_private_repo_topic.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "conflict with include" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                repository_ids: [@org1_private_repo2.id]
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                ]
              })
            ))

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "topic:#{@org1_private_repo_topic.name},#{@org1_private_repo2_topic.name} -topic:#{@org1_private_repo_topic.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 1)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "conflict with exclude" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "topic:#{@org1_private_repo_topic.name} -topic:#{@org1_private_repo_topic.name},#{@org1_private_repo2_topic.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "invalid value" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: [@org1, @org2],
              query: "topic:woof"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "caps number of repo IDs sent" do
            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: includes(@org1.id, @org2.id),
                repository_ids: any_of([@org1_private_repo.id], [@org1_repo_with_topics.id])
              )
            )).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                ]
              })
            ))

            AlertQueryService::BusinessScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
              service = AlertQueryService.for_business(
                user: @org_admin,
                user_session: @user_session,
                business: @business,
                organizations: [@org1, @org2],
                query: "topic:#{@org1_private_repo_topic.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end
          end
        end

        context "bad org filter values" do
          test "don't call turboscan because owner_ids is empty" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:foo"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end
        end
      end

      context "organization-level" do
        context "user can access all repos in the org" do
          context "no repos are selected" do
            test "passes no repo IDs to Turboscan" do
              GitHub::Turboscan
                .expects(:alerts_by_repo)
                .once
                .with(@default_alerts_by_repo_args.merge(owner_ids: [@org1.id]))
                .returns(
                  Twirp::ClientResp.new(
                    data: Turboscan::Proto::AlertsByRepoResponse.new({
                      open_count: 2,
                      resolved_count: 0,
                      results: [
                        Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result }),
                        Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                      ]
                    })
                  )
                )

              service = AlertQueryService.for_organization(user: @org_admin, user_session: @user_session, organization: @org1)

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 2)
              assert_equal(2, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end
          end

          context "repos from the org are selected" do
            test "passes all selected repo IDs to Turboscan" do
              GitHub::Turboscan
                .expects(:alerts_by_repo)
                .once
                .with(
                  @default_alerts_by_repo_args.merge(
                    owner_ids: [@org1.id],
                    repository_ids: [@org1_public_repo.id]
                  )
                )
                .returns(
                  Twirp::ClientResp.new(
                    data: Turboscan::Proto::AlertsByRepoResponse.new({
                      open_count: 1,
                      resolved_count: 0,
                      results: [Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })]
                    })
                  )
                )

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "repo:#{@org1_public_repo.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "caps number of repo IDs sent to Turboscan" do
              GitHub::Turboscan
                .expects(:alerts_by_repo)
                .once
                .with(has_entries(
                  @default_alerts_by_repo_args.merge(
                    owner_ids: [@org1.id],
                    repository_ids: any_of([@org1_public_repo.id], [@org1_private_repo.id])
                  )
                ))
                .returns(
                  Twirp::ClientResp.new(
                    data: Turboscan::Proto::AlertsByRepoResponse.new({
                      open_count: 1,
                      resolved_count: 0,
                      results: [Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })]
                    })
                  )
                )

              AlertQueryService::OrganizationScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
                service = AlertQueryService.for_organization(
                  user: @org_admin,
                  user_session: @user_session,
                  organization: @org1,
                  query: "repo:#{@org1_public_repo.name},#{@org1_private_repo.name}"
                )

                alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
                assert_equal(alerts.size, 1)
                assert_equal(1, open_count)
                assert_equal(0, closed_count)
                refute(has_error)
              end
            end
          end

          context "repos from another org are selected" do
            test "passes only selected repo IDs from the current org to Turboscan" do
              GitHub::Turboscan
                .expects(:alerts_by_repo)
                .once
                .with(
                  @default_alerts_by_repo_args.merge(
                    owner_ids: [@org1.id],
                    repository_ids: [@org1_public_repo.id]
                  )
                )
                .returns(
                  Twirp::ClientResp.new(
                    data: Turboscan::Proto::AlertsByRepoResponse.new({
                      open_count: 0,
                      resolved_count: 1,
                      results: [Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })]
                    })
                  )
                )

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "repo:#{@org1_public_repo.name},#{@org2_private_repo.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(0, open_count)
              assert_equal(1, closed_count)
              refute(has_error)
            end
          end

          context "team filter" do
            test "single include" do
              GitHub::Turboscan.expects(:alerts_by_repo).once.with(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  repository_ids: [@org1_private_repo.id]
                )
              ).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                  ]
                })
              ))

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "team:#{@org1_secret_team.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "single exclude" do
              GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  excluded_repository_ids: [@org1_private_repo.id]
                )
              )).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })
                  ]
                })
              ))

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "-team:#{@org1_secret_team.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "single conflict" do
              GitHub::Turboscan.expects(:alerts_by_repo).never

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "team:#{@org1_secret_team.name} -team:#{@org1_secret_team.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 0)
              assert_equal(0, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "conflict with include" do
              GitHub::Turboscan.expects(:alerts_by_repo).once.with(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  repository_ids: [@org1_private_repo2.id]
                )
              ).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                  ]
                })
              ))

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "team:#{@org1_secret_team.name},#{@org1_secret_team2.name} -team:#{@org1_secret_team.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "conflict with exclude" do
              GitHub::Turboscan.expects(:alerts_by_repo).never

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "team:#{@org1_secret_team.name} -team:#{@org1_secret_team.name},#{@org1_secret_team2.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 0)
              assert_equal(0, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "invalid value" do
              GitHub::Turboscan.expects(:alerts_by_repo).never

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "team:woof"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 0)
              assert_equal(0, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "user permissions to see team" do
              member = create(:user)
              @org1.add_member(member)
              query = "team:#{@org1_secret_team.name}"
              GitHub::Turboscan.expects(:alerts_by_repo).never
              service = AlertQueryService.for_organization(user: member, user_session: @user_session, organization: @org1, query: query)
              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 0)
              assert_equal(0, open_count)
              assert_equal(0, closed_count)
              refute(has_error)

              query = "team:#{@org1_public_team.name}"
              GitHub::Turboscan.expects(:alerts_by_repo).once.with(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  repository_ids: [@org1_public_repo.id]
                )
              ).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })
                  ]
                })
              ))
              service = AlertQueryService.for_organization(user: member, user_session: @user_session, organization: @org1, query: query)
              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "caps number of repo IDs sent" do
              ::SecurityCenter::FeatureFlagHelper.stubs(:code_scanning_teams_filter_enabled?).returns(true)

              GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  repository_ids: any_of([@org1_private_repo.id], [@org1_private_repo2.id])
                ))
              ).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                  ]
                })
              ))

              AlertQueryService::OrganizationScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
                service = AlertQueryService.for_organization(
                  user: @org_admin,
                  user_session: @user_session,
                  organization: @org1,
                  query: "team:#{@org1_secret_team.name},#{@org1_secret_team2.name}"
                )

                alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
                assert_equal(alerts.size, 1)
                assert_equal(1, open_count)
                assert_equal(0, closed_count)
                refute(has_error)
              end
            end
          end

          context "topic filter" do
            test "single include" do
              GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  repository_ids: includes(@org1_private_repo.id, @org1_repo_with_topics.id)
                )
              )).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result }),
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_repo_with_topics.id, result: @default_turboscan_result })
                  ]
                })
              ))

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "topic:#{@org1_private_repo_topic.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 2)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "single exclude" do
              GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  excluded_repository_ids: [@org1_private_repo.id, @org1_repo_with_topics.id]
                )
              )).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo2.id, result: @default_turboscan_result }),
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })
                  ]
                })
              ))

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "-topic:#{@org1_private_repo_topic.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 2)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "single conflict" do
              GitHub::Turboscan.expects(:alerts_by_repo).never

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "topic:#{@org1_private_repo_topic.name} -topic:#{@org1_private_repo_topic.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 0)
              assert_equal(0, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "conflict with include" do
              GitHub::Turboscan.expects(:alerts_by_repo).once.with(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  repository_ids: [@org1_private_repo2.id]
                )
              ).returns(Twirp::ClientResp.new(
                data: Turboscan::Proto::AlertsByRepoResponse.new({
                  open_count: 1,
                  resolved_count: 0,
                  results: [
                    Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                  ]
                })
              ))

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "topic:#{@org1_private_repo_topic.name},#{@org1_private_repo2_topic.name} -topic:#{@org1_private_repo_topic.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "conflict with exclude" do
              GitHub::Turboscan.expects(:alerts_by_repo).never

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "topic:#{@org1_private_repo_topic.name} -topic:#{@org1_private_repo_topic.name},#{@org1_private_repo2_topic.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 0)
              assert_equal(0, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end

            test "invalid value" do
              GitHub::Turboscan.expects(:alerts_by_repo).never

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "topic:woof"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 0)
              assert_equal(0, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end
          end

          test "caps number of repo IDs sent" do
            ::SecurityCenter::FeatureFlagHelper.stubs(:code_scanning_topic_filter_enabled?).returns(true)

            GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries(
              @default_alerts_by_repo_args.merge(
                owner_ids: [@org1.id],
                repository_ids: any_of([@org1_private_repo.id], [@org1_repo_with_topics.id])
              ))
            ).returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::AlertsByRepoResponse.new({
                open_count: 1,
                resolved_count: 0,
                results: [
                  Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })
                ]
              })
            ))

            AlertQueryService::OrganizationScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                query: "topic:#{@org1_private_repo_topic.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(0, closed_count)
              refute(has_error)
            end
          end
        end

        context "allowed_repository_ids is populated" do
          context "no repos are selected" do
            test "passes allowed repo IDs to Turboscan" do
              GitHub::Turboscan
                .expects(:alerts_by_repo)
                .once
                .with(
                  @default_alerts_by_repo_args.merge(
                    owner_ids: [@org1.id],
                    repository_ids: [@org1_private_repo.id]
                  )
                )
                .returns(
                  Twirp::ClientResp.new(
                    data: Turboscan::Proto::AlertsByRepoResponse.new({
                      open_count: 1,
                      resolved_count: 1,
                      results: [Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result })]
                    })
                  )
                )

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                allowed_repository_ids: [@org1_private_repo.id]
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(1, closed_count)
              refute(has_error)
            end
          end

          context "non-allowed repos are selected" do
            test "passes only allowed repo IDs to Turboscan" do
              GitHub::Turboscan
                .expects(:alerts_by_repo)
                .once
                .with(
                  @default_alerts_by_repo_args.merge(
                    owner_ids: [@org1.id],
                    repository_ids: [@org1_public_repo.id]
                  )
                )
                .returns(
                  Twirp::ClientResp.new(
                    data: Turboscan::Proto::AlertsByRepoResponse.new({
                      open_count: 1,
                      resolved_count: 1,
                      results: [Turboscan::Proto::RepoResult.new({ repository_id: @org1_public_repo.id, result: @default_turboscan_result })]
                    })
                  )
                )

              service = AlertQueryService.for_organization(
                user: @org_admin,
                user_session: @user_session,
                organization: @org1,
                allowed_repository_ids: [@org1_public_repo.id],
                query: "repo:#{@org1_public_repo.name},#{@org1_private_repo.name}"
              )

              alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
              assert_equal(alerts.size, 1)
              assert_equal(1, open_count)
              assert_equal(1, closed_count)
              refute(has_error)
            end
          end
        end

        context "allowed_repository_ids is []" do
          test "a Turboscan request does not occur" do
            GitHub::Turboscan.expects(:alerts_by_repo).never

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              allowed_repository_ids: [],
              query: "repo:#{@org1_public_repo.name},#{@org2_private_repo.name}"
            )

            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 0)
            assert_equal(0, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end
        end
      end
    end

    context "#repository_ids_for_repo_menu" do
      context "business-level" do
        test "it ignores selected repos when repo name filters are applied" do
          GitHub::Turboscan
            .expects(:repository_ids_for_org)
            .once
            .with(has_entries(@default_repository_ids_for_org_args.merge(owner_ids: includes(@org1.id, @org2.id))))
            .returns(
              Twirp::ClientResp.new(
                data: Turboscan::Proto::RepositoryIDsResponse.new(
                  repositories: [
                    Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                      alert_count: 1,
                      repository_id: @org1_public_repo.id
                    }),
                    Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                      alert_count: 1,
                      repository_id: @org1_private_repo.id
                    }),
                    Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                      alert_count: 1,
                      repository_id: @org2_public_repo.id
                    }),
                    Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                      alert_count: 1,
                      repository_id: @org2_private_repo.id
                    })
                  ]
                )
              )
            )

          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: @business.organizations,
            query: "repo:#{@org1_public_repo.name}"
          )

          assert_equal(service.repository_ids_for_repo_menu.size, 4)
        end

        test "it adds selected ids when team filter is applied" do
          GitHub::Turboscan
          .expects(:repository_ids_for_org)
          .once
          .with(has_entries(@default_repository_ids_for_org_args
            .merge(owner_ids: includes(@org1.id, @org2.id), repository_ids: [@org1_private_repo.id])))
          .returns(Twirp::ClientResp.new(
            data: Turboscan::Proto::RepositoryIDsResponse.new(
              repositories: [
                Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                  alert_count: 1,
                  repository_id: @org1_private_repo.id
                }),
              ]
            )
          ))

          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: [@org1, @org2],
            query: "team:#{@org1_secret_team.name}"
          )

          assert_equal(service.repository_ids_for_repo_menu.size, 1)
        end

        test "it adds selected ids when topic filter is applied" do
          GitHub::Turboscan
          .expects(:repository_ids_for_org)
          .once
          .with(has_entries(@default_repository_ids_for_org_args
            .merge(owner_ids: includes(@org1.id, @org2.id), repository_ids: includes(@org1_private_repo.id, @org1_repo_with_topics.id))))
          .returns(Twirp::ClientResp.new(
            data: Turboscan::Proto::RepositoryIDsResponse.new(
              repositories: [
                Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                  alert_count: 1,
                  repository_id: @org1_private_repo.id
                }),
              ]
            )
          ))

          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: [@org1, @org2],
            query: "topic:#{@org1_private_repo_topic.name}"
          )

          assert_equal(service.repository_ids_for_repo_menu.size, 1)
        end

        context "no orgs are selected" do
          test "it adds all authorized org IDs to the request" do
            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(has_entries(@default_repository_ids_for_org_args.merge(owner_ids: includes(@org1.id, @org2.id))))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RepositoryIDsResponse.new(
                    repositories: [
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_public_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_private_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org2_public_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org2_private_repo.id
                      })
                    ]
                  )
                )
              )

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations
            )

            assert_equal(service.repository_ids_for_repo_menu.size, 4)
          end
        end

        context "orgs are selected" do
          test "it adds authorized selected org IDs to the request" do
            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(@default_repository_ids_for_org_args.merge(owner_ids: [@org1.id]))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RepositoryIDsResponse.new(
                    repositories: [
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_public_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_private_repo.id
                      })
                    ]
                  )
                )
              )

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:#{@org1.name}"
            )

            assert_equal(service.repository_ids_for_repo_menu.size, 2)
          end
        end

        context "bad org filter values" do
          test "don't call turboscan because owner_ids is empty" do
            GitHub::Turboscan.expects(:repository_ids_for_org).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:foo"
            )

            assert_equal(service.repository_ids_for_repo_menu.size, 0)
          end
        end
      end

      context "organization-level" do
        context "user can access all repos in the org" do
          test "it ignores selected repos when repo name filters are applied" do
            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(@default_repository_ids_for_org_args.merge(owner_ids: [@org1.id]))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              query: "repo:#{@org1_public_repo.name}"
            )
            service.repository_ids_for_repo_menu
          end

          test "it adds selected ids when team filter is applied" do
            ::SecurityCenter::FeatureFlagHelper.stubs(:code_scanning_teams_filter_enabled?).returns(true)

            GitHub::Turboscan
            .expects(:repository_ids_for_org)
            .once
            .with(@default_repository_ids_for_org_args
              .merge(owner_ids: [@org1.id], repository_ids: [@org1_private_repo.id]))
            .returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::RepositoryIDsResponse.new(
                repositories: [
                  Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                    alert_count: 1,
                    repository_id: @org1_private_repo.id
                  }),
                ]
              )
            ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              query: "team:#{@org1_secret_team.name}"
            )

            assert_equal(service.repository_ids_for_repo_menu.size, 1)
          end

          test "it adds selected ids when topic filter is applied" do
            ::SecurityCenter::FeatureFlagHelper.stubs(:code_scanning_topic_filter_enabled?).returns(true)

            GitHub::Turboscan
            .expects(:repository_ids_for_org)
            .once
            .with(has_entries(@default_repository_ids_for_org_args
              .merge(owner_ids: [@org1.id], repository_ids: includes(@org1_private_repo.id, @org1_repo_with_topics.id))))
            .returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::RepositoryIDsResponse.new(
                repositories: [
                  Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                    alert_count: 1,
                    repository_id: @org1_private_repo.id
                  }),
                  Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                    alert_count: 1,
                    repository_id: @org1_public_repo.id
                  }),
                ]
              )
            ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              query: "topic:#{@org1_private_repo_topic.name}"
            )

            assert_equal(service.repository_ids_for_repo_menu.size, 2)
          end
        end

        context "allowed_repository_ids is present" do
          test "it assigns allowed_repository_ids to repository_ids in the request" do
            allowed_repository_ids = [@org1_private_repo.id]

            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(@default_repository_ids_for_org_args.merge(
                owner_ids: [@org1.id],
                repository_ids: allowed_repository_ids
              ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              allowed_repository_ids: allowed_repository_ids
            )
            service.repository_ids_for_repo_menu
          end

          test "it ignores selected repos when repo name filters are applied" do
            allowed_repository_ids = [@org1_private_repo.id]

            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(@default_repository_ids_for_org_args.merge(
                owner_ids: [@org1.id],
                repository_ids: allowed_repository_ids
              ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              allowed_repository_ids: allowed_repository_ids,
              query: "repo:#{@org1_public_repo.name}"
            )
            service.repository_ids_for_repo_menu
          end
        end

        context "with repo_numbers" do
          test "it adds repo_numbers to the request" do
            repo_numbers = [
              Turboscan::Proto::RepoNumber.new({
                number: 1,
                repository_id: @org1_public_repo.id,
              })
              ].map(&:to_h)

            GitHub::Turboscan
            .expects(:repository_ids_for_org)
            .once
            .with(@default_repository_ids_for_org_args.merge(
              owner_ids: [@org1.id],
              filter: @default_repository_ids_for_org_args[:filter].merge(repo_numbers:)
              ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              query: "repo:#{@org1_public_repo.name}",
              repo_numbers:
            )
            service.repository_ids_for_repo_menu
          end
        end
      end
    end

    context "#repository_ids_from_filters" do
      context "business-level" do
        test "it adds selected ids when team filter is applied" do
          GitHub::Turboscan
          .expects(:repository_ids_for_org)
          .once
          .with(has_entries(@default_repository_ids_for_org_args
            .merge(owner_ids: includes(@org1.id, @org2.id), repository_ids: [@org1_private_repo.id])))
          .returns(Twirp::ClientResp.new(
            data: Turboscan::Proto::RepositoryIDsResponse.new(
              repositories: [
                Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                  alert_count: 1,
                  repository_id: @org1_private_repo.id
                }),
              ]
            )
          ))

          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: [@org1, @org2],
            query: "team:#{@org1_secret_team.name}"
          )

          assert_equal(service.repository_ids_from_filters.size, 1)
        end

        test "it adds selected ids when topic filter is applied" do
          GitHub::Turboscan
          .expects(:repository_ids_for_org)
          .once
          .with(has_entries(@default_repository_ids_for_org_args
            .merge(owner_ids: includes(@org1.id, @org2.id), repository_ids: includes(@org1_private_repo.id, @org1_repo_with_topics.id))))
          .returns(Twirp::ClientResp.new(
            data: Turboscan::Proto::RepositoryIDsResponse.new(
              repositories: [
                Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                  alert_count: 1,
                  repository_id: @org1_private_repo.id
                }),
              ]
            )
          ))

          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: [@org1, @org2],
            query: "topic:#{@org1_private_repo_topic.name}"
          )

          assert_equal(service.repository_ids_from_filters.size, 1)
        end

        context "no orgs are selected" do
          test "it adds all authorized org IDs to the request" do
            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(has_entries(@default_repository_ids_for_org_args.merge(owner_ids: includes(@org1.id, @org2.id))))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RepositoryIDsResponse.new(
                    repositories: [
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_public_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_private_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org2_public_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org2_private_repo.id
                      })
                    ]
                  )
                )
              )

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations
            )

            assert_equal(service.repository_ids_from_filters.size, 4)
          end
        end

        context "orgs are selected" do
          test "it adds authorized selected org IDs to the request" do
            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(@default_repository_ids_for_org_args.merge(owner_ids: [@org1.id]))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RepositoryIDsResponse.new(
                    repositories: [
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_public_repo.id
                      }),
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_private_repo.id
                      })
                    ]
                  )
                )
              )

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:#{@org1.name}"
            )

            assert_equal(service.repository_ids_from_filters.size, 2)
          end
        end

        context "bad org filter values" do
          test "don't call turboscan because owner_ids is empty" do
            GitHub::Turboscan.expects(:repository_ids_for_org).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:foo"
            )

            assert_equal(service.repository_ids_from_filters.size, 0)
          end
        end
      end

      context "organization-level" do
        context "user can access all repos in the org" do
          test "it adds selected ids when team filter is applied" do
            ::SecurityCenter::FeatureFlagHelper.stubs(:code_scanning_teams_filter_enabled?).returns(true)

            GitHub::Turboscan
            .expects(:repository_ids_for_org)
            .once
            .with(@default_repository_ids_for_org_args
              .merge(owner_ids: [@org1.id], repository_ids: [@org1_private_repo.id]))
            .returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::RepositoryIDsResponse.new(
                repositories: [
                  Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                    alert_count: 1,
                    repository_id: @org1_private_repo.id
                  }),
                ]
              )
            ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              query: "team:#{@org1_secret_team.name}"
            )

            assert_equal(service.repository_ids_from_filters.size, 1)
          end

          test "it adds selected ids when topic filter is applied" do
            ::SecurityCenter::FeatureFlagHelper.stubs(:code_scanning_topic_filter_enabled?).returns(true)

            GitHub::Turboscan
            .expects(:repository_ids_for_org)
            .once
            .with(has_entries(@default_repository_ids_for_org_args
              .merge(owner_ids: [@org1.id], repository_ids: includes(@org1_private_repo.id, @org1_repo_with_topics.id))))
            .returns(Twirp::ClientResp.new(
              data: Turboscan::Proto::RepositoryIDsResponse.new(
                repositories: [
                  Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                    alert_count: 1,
                    repository_id: @org1_private_repo.id
                  }),
                  Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                    alert_count: 1,
                    repository_id: @org1_public_repo.id
                  }),
                ]
              )
            ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              query: "topic:#{@org1_private_repo_topic.name}"
            )

            assert_equal(service.repository_ids_from_filters.size, 2)
          end
        end

        context "allowed_repository_ids is present" do
          test "it assigns allowed_repository_ids to repository_ids in the request" do
            allowed_repository_ids = [@org1_private_repo.id]

            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(@default_repository_ids_for_org_args.merge(
                owner_ids: [@org1.id],
                repository_ids: allowed_repository_ids
              ))

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              allowed_repository_ids: allowed_repository_ids
            )
            service.repository_ids_from_filters
          end
        end
      end
    end

    context "#rules_for_org" do
      context "business-level" do
        test "it adds all authorized orgs to the request" do
          GitHub::Turboscan
            .expects(:rules_for_org)
            .once
            .with(has_entries(@default_rules_for_org_args.merge(owner_ids: includes(@org1.id, @org2.id))))
            .returns(
              Twirp::ClientResp.new(
                data: Turboscan::Proto::RulesForOrgResponse.new(
                  rules: [
                    Turboscan::Proto::OrgRule.new(alert_count: 1),
                    Turboscan::Proto::OrgRule.new(alert_count: 1)
                  ]
                )
              )
            )
          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: @business.organizations
          )
          assert_equal(service.rules_for_org.size, 2)
        end

        context "bad org filter values" do
          test "don't call turboscan because owner_ids is empty" do
            GitHub::Turboscan.expects(:rules_for_org).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:foo"
            )

            assert_equal(service.rules_for_org.size, 0)
          end
        end
      end

      context "organization-level" do
        context "user can access all repos in the org" do
          test "it does not add repository_ids to the request" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .once
              .with(@default_rules_for_org_args.merge(owner_ids: [@org1.id]))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RulesForOrgResponse.new(
                    rules: [
                      Turboscan::Proto::OrgRule.new(alert_count: 1),
                      Turboscan::Proto::OrgRule.new(alert_count: 1)
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(user: @org_admin, user_session: @user_session, organization: @org1)
            assert_equal(service.rules_for_org.size, 2)
          end
        end

        context "with repo_numbers" do
          test "it adds repo_numbers to the request" do
            repo_numbers = [
              Turboscan::Proto::RepoNumber.new({
                number: 1,
                repository_id: @org1_private_repo.id,
              }), Turboscan::Proto::RepoNumber.new({
                number: 2,
                repository_id: @org1_repo_with_topics.id,
              })
              ].map(&:to_h)

            GitHub::Turboscan
              .expects(:rules_for_org)
              .once
              .with(@default_rules_for_org_args.merge(
                owner_ids: [@org1.id],
                filter: @default_rules_for_org_args[:filter].merge(repo_numbers:)
                ))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RulesForOrgResponse.new(
                    rules: [
                      Turboscan::Proto::OrgRule.new(alert_count: 1),
                      Turboscan::Proto::OrgRule.new(alert_count: 1)
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(user: @org_admin, user_session: @user_session, organization: @org1, repo_numbers:)
            assert_equal(service.rules_for_org.size, 2)
          end
        end
      end
    end

    context "#rule_tags_for_org" do
      context "business-level" do
        test "it adds all authorized orgs to the request" do
          GitHub::Turboscan
            .expects(:rule_tags_for_org)
            .once
            .with(has_entries(@default_rule_tags_for_org_args.merge(owner_ids: includes(@org1.id, @org2.id))))
            .returns(
              Twirp::ClientResp.new(
                data: Turboscan::Proto::RuleTagsForOrgResponse.new(
                  rule_tags: [
                    Turboscan::Proto::OrgRuleTag.new(tag: "tag1"),
                    Turboscan::Proto::OrgRuleTag.new(tag: "tag2")
                  ]
                )
              )
            )
          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: @business.organizations
          )
          assert_equal(service.rule_tags_for_org.size, 2)
        end

        context "bad org filter values" do
          test "don't call turboscan because owner_ids is empty" do
            GitHub::Turboscan.expects(:rule_tags_for_org).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:foo"
            )

            assert_equal(service.rule_tags_for_org.size, 0)
          end
        end
      end

      context "organization-level" do
        context "user can access all repos in the org" do
          test "it does not add repository_ids to the request" do
            GitHub::Turboscan
              .expects(:rule_tags_for_org)
              .once
              .with(@default_rule_tags_for_org_args.merge(owner_ids: [@org1.id]))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RuleTagsForOrgResponse.new(
                    rule_tags: [
                      Turboscan::Proto::OrgRuleTag.new(tag: "tag1"),
                      Turboscan::Proto::OrgRuleTag.new(tag: "tag2")
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(user: @org_admin, user_session: @user_session, organization: @org1)
            assert_equal(service.rule_tags_for_org.size, 2)
          end
        end
      end
    end

    context "#severities_for_org" do
      context "business-level" do
        test "it adds all authorized orgs to the request" do
          GitHub::Turboscan
            .expects(:severities_for_org)
            .once
            .with(has_entries(@default_severities_for_org_args.merge(owner_ids: includes(@org1.id, @org2.id))))
            .returns(
              Twirp::ClientResp.new(
                data: Turboscan::Proto::SeveritiesForOrgResponse.new(
                  severities: [
                    Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 1),
                    Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 1)
                  ]
                )
              )
            )
          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: @business.organizations
          )
          assert_equal(service.severities_for_org.size, 2)
        end

        context "bad org filter values" do
          test "don't call turboscan because owner_ids is empty" do
            GitHub::Turboscan.expects(:severities_for_org).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:foo"
            )

            assert_equal(service.severities_for_org.size, 0)
          end
        end
      end

      context "organization-level" do
        context "user can access all repos in the org" do
          test "it does not add repository_ids to the request" do
            GitHub::Turboscan
              .expects(:severities_for_org)
              .once
              .with(@default_severities_for_org_args.merge(owner_ids: [@org1.id]))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::SeveritiesForOrgResponse.new(
                    severities: [
                      Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 1),
                      Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 1)
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(user: @org_admin, user_session: @user_session, organization: @org1)
            assert_equal(service.severities_for_org.size, 2)
          end
        end
      end
    end

    context "#tool_names_for_org" do
      context "business-level" do
        test "it adds all authorized orgs to the request" do
          GitHub::Turboscan
            .expects(:tool_names_for_org)
            .once
            .with(has_entries(@default_tool_names_for_org_args.merge(owner_ids: includes(@org1.id, @org2.id))))
            .returns(
              Twirp::ClientResp.new(
                data: Turboscan::Proto::ToolNamesResponse.new(
                  tools: [
                    Turboscan::Proto::ToolDescription.new(name: "tool1"),
                    Turboscan::Proto::ToolDescription.new(name: "tool2")
                  ]
                )
              )
            )
          service = AlertQueryService.for_business(
            user: @org_admin,
            user_session: @user_session,
            business: @business,
            organizations: @business.organizations
          )
          assert_equal(service.tool_names_for_org.size, 2)
        end

        context "bad org filter values" do
          test "don't call turboscan because owner_ids is empty" do
            GitHub::Turboscan.expects(:tool_names_for_org).never

            service = AlertQueryService.for_business(
              user: @org_admin,
              user_session: @user_session,
              business: @business,
              organizations: @business.organizations,
              query: "org:foo"
            )

            assert_equal(service.tool_names_for_org.size, 0)
          end
        end
      end

      context "organization-level" do
        context "user can access all repos in the org" do
          test "it does not add repository_ids to the request" do
            GitHub::Turboscan
              .expects(:tool_names_for_org)
              .once
              .with(@default_tool_names_for_org_args.merge(owner_ids: [@org1.id]))
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::ToolNamesResponse.new(
                    tools: [
                      Turboscan::Proto::ToolDescription.new(name: "tool1"),
                      Turboscan::Proto::ToolDescription.new(name: "tool2")
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(user: @org_admin, user_session: @user_session, organization: @org1)
            assert_equal(service.tool_names_for_org.size, 2)
          end
        end

        context "with repo_numbers" do
          test "it adds repo_numbers to the request" do
            repo_numbers = [
              Turboscan::Proto::RepoNumber.new({
                number: 1,
                repository_id: @org1_private_repo.id,
              }), Turboscan::Proto::RepoNumber.new({
                number: 2,
                repository_id: @org1_repo_with_topics.id,
              })
              ].map(&:to_h)

            GitHub::Turboscan
            .expects(:tool_names_for_org)
            .once
            .with(@default_tool_names_for_org_args.merge(
              owner_ids: [@org1.id],
              filter: @default_tool_names_for_org_args[:filter].merge(repo_numbers:)
              ))
            .returns(
              Twirp::ClientResp.new(
                data: Turboscan::Proto::ToolNamesResponse.new(
                  tools: [
                    Turboscan::Proto::ToolDescription.new(name: "tool1"),
                    Turboscan::Proto::ToolDescription.new(name: "tool2")
                  ]
                )
              )
            )

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              repo_numbers:
            )
            assert_equal(service.tool_names_for_org.size, 2)
          end
        end

        context "visibility" do
          test "properly passes visibility to a alert query" do
            GitHub::Turboscan
              .expects(:alerts_by_repo)
              .once
              .with(
                @default_alerts_by_repo_args.merge(
                  owner_ids: [@org1.id],
                  repository_visibilities: [:REPOSITORY_VISIBILITY_PRIVATE]
                )
              ).returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::AlertsByRepoResponse.new({
                    open_count: 1,
                    resolved_count: 0,
                    results: [
                      Turboscan::Proto::RepoResult.new({ repository_id: @org1_private_repo.id, result: @default_turboscan_result }),
                    ]
                  })
                )
              )
            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              visibility: "private"
            )
            alerts, repos_by_id, open_count, closed_count, has_error = service.alerts_by_repo
            assert_equal(alerts.size, 1)
            assert_equal(1, open_count)
            assert_equal(0, closed_count)
            refute(has_error)
          end

          test "properly passes visibility to a tool filter query" do
            GitHub::Turboscan
              .expects(:tool_names_for_org)
              .once
              .with(
                @default_tool_names_for_org_args.merge(
                  owner_ids: [@org1.id],
                  filter: @default_tool_names_for_org_args[:filter].merge(
                    repository_visibilities: [:REPOSITORY_VISIBILITY_PRIVATE]
                  )
                )
              ).returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::ToolNamesResponse.new(
                    tools: [
                      Turboscan::Proto::ToolDescription.new(name: "tool1"),
                      Turboscan::Proto::ToolDescription.new(name: "tool2")
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              visibility: "private"
            )
            assert_equal(service.tool_names_for_org.size, 2)
          end

          test "properly passes visibility to a repositories filter query" do
            GitHub::Turboscan
              .expects(:repository_ids_for_org)
              .once
              .with(
                @default_repository_ids_for_org_args.merge(
                  owner_ids: [@org1.id],
                  filter: @default_repository_ids_for_org_args[:filter].merge(
                    repository_visibilities: [:REPOSITORY_VISIBILITY_PRIVATE]
                  )
                )
              ).returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RepositoryIDsResponse.new(
                    repositories: [
                      Turboscan::Proto::RepositoryIDsResponse::Repository.new({
                        alert_count: 1,
                        repository_id: @org1_private_repo.id
                      })
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              visibility: "private"
            )
            assert_equal(service.repository_ids_from_filters.size, 1)
          end

          test "properly passes visibility to a rule filter query" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .once
              .with(
                @default_rules_for_org_args.merge(
                  owner_ids: [@org1.id],
                  filter: @default_rules_for_org_args[:filter].merge(
                    repository_visibilities: [:REPOSITORY_VISIBILITY_PRIVATE]
                  )
                )
              ).returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::RulesForOrgResponse.new(
                    rules: [
                      Turboscan::Proto::OrgRule.new(alert_count: 1),
                      Turboscan::Proto::OrgRule.new(alert_count: 1)
                    ]
                  )
                )
              )

            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              visibility: "private"
            )
            assert_equal(service.rules_for_org.size, 2)
          end

          test "properly passes visibility to a severity filter query" do
            GitHub::Turboscan
              .expects(:severities_for_org)
              .once
              .with(
                @default_severities_for_org_args.merge(
                  owner_ids: [@org1.id],
                  filter: @default_severities_for_org_args[:filter].merge(
                    repository_visibilities: [:REPOSITORY_VISIBILITY_PRIVATE]
                  )
                )
              ).returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::SeveritiesForOrgResponse.new(
                    severities: [
                      Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 1),
                      Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 1)
                    ]
                  )
                )
              )
            service = AlertQueryService.for_organization(
              user: @org_admin,
              user_session: @user_session,
              organization: @org1,
              visibility: "private"
            )
            assert_equal(service.severities_for_org.size, 2)
          end
        end
      end
    end

    context "#counts_by_repo" do
      test "calls turboscan with the correct arguments and included repos" do
        GitHub::Turboscan
          .expects(:counts_by_repo)
          .once
          .with({
            owner_ids: [@org1.id],
            repository_ids: [@org1_private_repo.id],
            excluded_repository_ids: [],
            filter: @default_alerts_filter,
          }).returns(
            Twirp::ClientResp.new(
              data: Turboscan::Proto::CountsByRepoResponse.new(
                repository_counts: [
                  Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new(
                    repository_id: @org1_private_repo.id,
                    open_count: 3,
                    closed_count: 2
                  )
                ]
              )
            )
          )

        service = AlertQueryService.for_organization(
          user: @org_admin,
          user_session: @user_session,
          organization: @org1,
          query: "repo:#{@org1_private_repo.nwo}"
        )

        repository_counts = service.counts_by_repo.first
        assert_equal(repository_counts.size, 1)
        assert_equal(repository_counts.first.open_count, 3)
        assert_equal(repository_counts.first.closed_count, 2)
      end

      test "calls turboscan with the correct arguments and excluded_repos" do
        GitHub::Turboscan
          .expects(:counts_by_repo)
          .once
          .with({
            owner_ids: [@org1.id],
            repository_ids: [],
            excluded_repository_ids: [@org1_private_repo2.id],
            filter: @default_alerts_filter,
          }).returns(
            Twirp::ClientResp.new(
              data: Turboscan::Proto::CountsByRepoResponse.new(
                repository_counts: [
                  Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new(
                    repository_id: @org1_private_repo.id,
                    open_count: 3,
                    closed_count: 2
                  )
                ]
              )
            )
          )

        service = AlertQueryService.for_organization(
          user: @org_admin,
          user_session: @user_session,
          organization: @org1,
          query: "-repo:#{@org1_private_repo2.nwo}"
        )

        repository_counts = service.counts_by_repo.first
        assert_equal(repository_counts.size, 1)
        assert_equal(repository_counts.first.open_count, 3)
        assert_equal(repository_counts.first.closed_count, 2)
      end

      test "returns an empty result when user has no access to any repo" do
        GitHub::Turboscan
          .expects(:counts_by_repo)
          .never

        service = AlertQueryService.for_organization(
          user: @org_admin,
          user_session: @user_session,
          organization: @org1,
          query: "repo:nonexistent",
          allowed_repository_ids: []
        )

        assert_equal [[], false, nil], service.counts_by_repo
      end
    end

    context "#counts_by_campaigns" do
      test "calls turboscan with the correct arguments" do
        campaign = create(:security_campaign, organization: @org1)
        GitHub::Turboscan
          .expects(:counts_by_campaigns)
          .once
          .with({
            owner_ids: [@org1.id],
            security_campaign_ids: [campaign.id],
            repository_ids: [@org1_private_repo.id],
            filter: {
              repo_numbers: [
                Turboscan::Proto::RepoNumber.new(
                  repository_id: @org1_private_repo.id,
                  number: 1,
                )
              ]
            }
          }).returns(
            Twirp::ClientResp.new(
              data: Turboscan::Proto::CountsByCampaignsResponse.new(
                campaign_counts: [{
                  campaign_id: campaign.id,
                  open_count: 3,
                  closed_count: 2,
                  open_with_links_count: 1,
                }]
              )
            )
          )

        service = AlertQueryService.for_organization(
          user: @org_admin,
          organization: @org1,
          user_session: nil,
          security_campaign_ids: [campaign.id],
          allowed_repository_ids: [@org1_private_repo.id],
          repo_numbers: [
            Turboscan::Proto::RepoNumber.new(
              repository_id: @org1_private_repo.id,
              number: 1,
            )
          ]
        )

        campaign_counts = service.counts_by_campaigns&.data&.campaign_counts || []
        assert_equal(campaign_counts.size, 1)
        assert_equal(campaign_counts.first.open_count, 3)
        assert_equal(campaign_counts.first.closed_count, 2)
      end

      test "returns nil when use has no access to any repo" do
        campaign = create(:security_campaign, organization: @org1)
        GitHub::Turboscan
          .expects(:counts_by_campaigns)
          .never

        service = AlertQueryService.for_organization(
          user: @org_admin,
          organization: @org1,
          user_session: nil,
          security_campaign_ids: [campaign.id],
          query: "repo:nonexistent",
          allowed_repository_ids: []
        )

        assert_nil(service.counts_by_campaigns)
      end
    end
  end
end
