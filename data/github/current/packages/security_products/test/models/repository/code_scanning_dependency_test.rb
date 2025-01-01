# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeScanningDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  EnabledDataMock = Struct.new(:is_enabled)
  fixtures do
    @user = create(:paid_user)
    @staff_user = create(:staff_admin_user)
    @org = create(:organization, admin: @user)
    @private_org_repo = create(:private_repository, owner: @org)
    @public_org_repo = create(:public_repository, owner: @org)
    @private_user_repo = create(:private_repository, owner: @user)
    @public_user_repo = create(:public_repository, owner: @user)

    @special_disabled_business = create(:business)
    @special_disabled_org = create(:organization, admin: @user)
    @special_disabled_business.add_organization(@special_disabled_org)
    @private_special_disabled_org_repo = create(:private_repository, :minimal, owner: @special_disabled_org)
    @public_special_disabled_org_repo = create(:public_repository, :minimal, owner: @special_disabled_org)
  end

  setup do
    reset_repo_root

    example_repo(:simple, @private_org_repo)
    example_repo(:simple, @public_org_repo)
    example_repo(:simple, @private_user_repo)
    example_repo(:simple, @public_user_repo)

    GitHub.flipper.enable(:code_scanning_enterprise_disabled, @special_disabled_business)
  end

  context "#default_code_scanning_ref_names_bytes" do
    test "returns an empty array for empty repos" do
      empty = create(:repository, :minimal)
      assert_equal [], empty.default_code_scanning_ref_names_bytes
    end

    test "includes the default branch" do
      assert_equal ["refs/heads/master"], @private_org_repo.default_code_scanning_ref_names_bytes
    end

    test "doesn't include protected branches" do
      oid = @private_org_repo.heads["master"].target_oid
      @private_org_repo.refs.create("refs/heads/protected1", oid, @private_org_repo.owner)
      @private_org_repo.refs.create("refs/heads/unprotected1", oid, @private_org_repo.owner)

      create(:protected_branch, repository: @private_org_repo, name: "protected1")

      # @private_org_repo is based on :simple_repo, which has a default branch of master
      assert_equal ["refs/heads/master"], @private_org_repo.default_code_scanning_ref_names_bytes
    end

    test "returns ref names even if they are not valid UTF-8" do
      Git::Ref.any_instance.expects(:qualified_name).at_least_once.returns("refs/heads/\xC8\xF2\x7F\xAF")
      assert_equal ["refs/heads/\xC8\xF2\x7F\xAF"], @private_org_repo.default_code_scanning_ref_names_bytes
    end
  end

  context "#default_code_scanning_ref_names" do
    test "returns an empty array for empty repos" do
      empty = create(:repository, :minimal)
      assert_equal [], empty.default_code_scanning_ref_names
    end

    test "includes the default branch" do
      assert_equal ["refs/heads/master"], @private_org_repo.default_code_scanning_ref_names
    end

    test "doesn't include protected branches" do
      oid = @private_org_repo.heads["master"].target_oid
      @private_org_repo.refs.create("refs/heads/protected1", oid, @private_org_repo.owner)
      @private_org_repo.refs.create("refs/heads/unprotected1", oid, @private_org_repo.owner)

      create(:protected_branch, repository: @private_org_repo, name: "protected1")

      # @private_org_repo is based on :simple_repo, which has a default branch of master
      assert_equal ["refs/heads/master"], @private_org_repo.default_code_scanning_ref_names
    end

    test "returns ref names as utf-8" do
      master = @private_org_repo.heads.find("master")
      branch = @private_org_repo.heads.create("unicode-#{GRIN_EMOJI}", master.target, @private_org_repo.owner)
      @private_org_repo.update_attribute(:default_branch, "unicode-#{GRIN_EMOJI}")

      assert_equal "UTF-8", @private_org_repo.default_code_scanning_ref_names.first.encoding.name
    end

    test "does not include refs with invalid utf-8" do
      Git::Ref.any_instance.expects(:qualified_name).at_least_once.returns("refs/heads/\xC8\xF2\x7F\xAF")

      assert_equal [], @private_org_repo.default_code_scanning_ref_names
    end
  end

  context "code_scanning_enabled?", skip_enterprise: true do
    test "returns false when disable_code_scanning feature flag is enabled" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      assert_equal true, @private_org_repo.code_scanning_enabled?

      @private_org_repo.enable_feature(:disable_code_scanning)

      assert_equal false, @private_org_repo.code_scanning_enabled?
    end

    test "returns true for private org repos who have purchased GHAS" do
      assert_equal :advanced_security_not_purchased, @private_org_repo.enable_advanced_security(actor: @user).error

      assert_equal false, @private_org_repo.code_scanning_enabled?

      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.reload.enable_advanced_security!(actor: @user)

      assert_equal true, @private_org_repo.reload.code_scanning_enabled?
    end

    test "returns false for private user-owned repositories regardless of purchasing GHAS" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)

      assert_equal false, @private_user_repo.code_scanning_enabled?
    end

    test "returns false for private org repos" do
      assert_equal false, @private_org_repo.code_scanning_enabled?
    end

    test "returns true for private repos owned by business that has bought advanced security" do
      business = create(:business)
      org = create(:organization, business: business)
      private_org_repo = create(:private_repository, :minimal, owner: org)

      refute private_org_repo.code_scanning_enabled?

      business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      private_org_repo.enable_advanced_security!(actor: User.ghost)

      assert private_org_repo.code_scanning_enabled?
    end

    test "returns false for private forks of public repos" do
      forker = create :user
      forked_repo = create(:fork_repository, forker: forker, fork_repo: @public_org_repo)
      forked_repo.set_visibility(actor: forker, visibility: "private") # MG: Could not find a way to fork directly as private.

      assert_equal false, forked_repo.code_scanning_enabled?
    end

    test "returns true for private repos owned by business that has bought advanced security and has turned GHAS on for the repo" do
      business = create(:business)
      org = create(:organization, admin: @user, business: business)
      private_org_repo = create(:private_repository, :minimal, owner: org)
      business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))

      refute private_org_repo.code_scanning_enabled?
      private_org_repo.enable_advanced_security!(actor: @user)
      assert private_org_repo.code_scanning_enabled?
    end

    test "returns false for private repos owned by business that has bought advanced security but has turned GHAS off for the repo" do
      business = create(:business)
      org = create(:organization, admin: @user, business: business)
      private_org_repo = create(:private_repository, :minimal, owner: org)
      business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      private_org_repo.enable_advanced_security!(actor: @user)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(false)

      assert private_org_repo.code_scanning_enabled?

      Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
        private_org_repo.disable_advanced_security!(actor: @user)
      end
      refute private_org_repo.code_scanning_enabled?
    end
  end

  context "code_scanning_enabled? on enterprise", enterprise_only: true do
    test "returns true only when config flag and license field are true" do
      GitHub::Enterprise.ensure_business!
      @public_org_repo.enable_advanced_security!(actor: @user)

      GitHub.stubs(:code_scanning_enabled?).returns(false)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      refute @public_org_repo.code_scanning_enabled?

      GitHub.stubs(:code_scanning_enabled?).returns(false)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      refute @public_org_repo.code_scanning_enabled?

      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      refute @public_org_repo.code_scanning_enabled?

      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      assert @public_org_repo.code_scanning_enabled?
    end
  end

  context "turboscan_considers_code_scanning_enabled?" do
    test "calls to turboscan if default_code_scanning_ref_names_bytes is nil" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)

      empty = create(:private_repository, :minimal, owner: @org)
      empty.enable_advanced_security!(actor: @user)

      assert_equal [], empty.default_code_scanning_ref_names_bytes

      GitHub::Turboscan.expects(:code_scanning_enabled?).once.with(
        repository_id: empty.id,
        default_ref_name_bytes: ""
      )

      empty.turboscan_considers_code_scanning_enabled?
    end

    test "returns false if repo has been deleted recently" do
      repo = create(:repository, owner: @org, from_example: :simple)

      repo.expects(:deleted?).returns(true)
      refute repo.turboscan_considers_code_scanning_enabled?
    end

    test "returns false if private repository does not have advanced security" do
      @private_org_repo.disable_advanced_security(actor: @user)

      refute @private_org_repo.turboscan_considers_code_scanning_enabled?
    end

    test "returns false if turboscan response is nil" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      GitHub::Turboscan.expects(:code_scanning_enabled?).once.with(
        repository_id: @private_org_repo.id,
        default_ref_name_bytes: @private_org_repo.default_code_scanning_ref_names_bytes.first
      ).returns(nil)

      refute @private_org_repo.turboscan_considers_code_scanning_enabled?
    end

    test "returns false if turboscan returns an error" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      GitHub::Turboscan.expects(:code_scanning_enabled?).once.with(
        repository_id: @private_org_repo.id,
        default_ref_name_bytes: @private_org_repo.default_code_scanning_ref_names_bytes.first
      ).returns(
        Twirp::ClientResp.new(
          error: "some error"
      ))

      refute @private_org_repo.turboscan_considers_code_scanning_enabled?
    end

    test "returns true if is_enabled from turboscan is true" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      GitHub::Turboscan.expects(:code_scanning_enabled?).once.with(
        repository_id: @private_org_repo.id,
        default_ref_name_bytes: @private_org_repo.default_code_scanning_ref_names_bytes.first
      ).returns(
        Twirp::ClientResp.new(
          data: EnabledDataMock.new(
            is_enabled: true
          )
      ))

      assert @private_org_repo.turboscan_considers_code_scanning_enabled?
    end

    test "returns false if is_enabled from turboscan is false" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      GitHub::Turboscan.expects(:code_scanning_enabled?).once.with(
        repository_id: @private_org_repo.id,
        default_ref_name_bytes: @private_org_repo.default_code_scanning_ref_names_bytes.first
      ).returns(
        Twirp::ClientResp.new(
          data: EnabledDataMock.new(
            is_enabled: false
          )
      ))

      refute @private_org_repo.turboscan_considers_code_scanning_enabled?
    end
  end

  context "code_scanning_analysis_exists_on_default_ref?" do
    test "returns false if turboscan response is nil" do
      GitHub::Turboscan.expects(:analyses).once.with(
        repository_id: @private_org_repo.id,
        ref_names_bytes: @private_org_repo.default_code_scanning_ref_names_bytes
      ).returns(nil)

      refute @private_org_repo.code_scanning_analysis_exists_on_default_ref?
    end

    test "returns false if total count is 0" do
      GitHub::Turboscan.expects(:analyses).once.with(
        repository_id: @private_org_repo.id,
        ref_names_bytes: @private_org_repo.default_code_scanning_ref_names_bytes
      ).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::AnalysesResponse.new(
            {
              analyses: [],
              total_count: 0,
              complete_analysis_exists: false,
            }
          )
        )
      )

      refute @private_org_repo.code_scanning_analysis_exists_on_default_ref?
    end

    test "returns true if total count is greater than 0" do
      GitHub::Turboscan.expects(:analyses).once.with(
        repository_id: @private_org_repo.id,
        ref_names_bytes: @private_org_repo.default_code_scanning_ref_names_bytes
      ).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::AnalysesResponse.new(
            {
              analyses: [],
              total_count: 2,
              complete_analysis_exists: true,
            }
          )
        )
      )

      assert @private_org_repo.code_scanning_analysis_exists_on_default_ref?
    end
  end

  context "code_scanning_review_security_center_status" do
    test "returns 'enrolled' if auto_codeql is enabled on a repo" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      Repository.any_instance.expects(:code_scanning_security_center_scanning_status).returns("enrolled")

      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)

      assert_equal "enrolled", @private_org_repo.code_scanning_review_security_center_status.scanning_status
    end

    test "returns 'enrolled' if there are recent prs with analyses on a repo" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      Repository.any_instance.expects(:code_scanning_security_center_scanning_status).returns("enrolled")

      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

      commit = create(:commit,
        repository: @private_org_repo,
        author: @user,
        branch: "cr-line-endings",
        changes: -> (files) {
          files.add("hello.rb", "puts 'Test'")
        }
      )
      pr = create(:pull_request,
        repository: @private_org_repo,
        base_user: @user,
        head_user: @user,
        base_ref: @private_org_repo.default_branch,
        head_ref: "cr-line-endings",
        user: @user
      )

      GitHub::Turboscan.expects(:analyses).at_least_once.with(
        repository_id: @private_org_repo.id,
        ref_names_bytes: ["refs/pull/#{pr.number}/merge".b, "refs/pull/#{pr.number}/head".b, "refs/heads/cr-line-endings"],
      ).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::AnalysesResponse.new(
            {
              analyses: [
                Turboscan::Proto::Analysis.new(commit_oid: pr.head_sha, tool_description: Turboscan::Proto::ToolDescription.new(name: "CodeQL")),
              ],
              total_count: 1,
              complete_analysis_exists: true,
            }
          )
        )
      )

      assert_equal "enrolled", @private_org_repo.code_scanning_review_security_center_status.scanning_status
    end

    test "returns 'not_enrolled' if code scanning has not been active on prs at all" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      Repository.any_instance.expects(:code_scanning_security_center_scanning_status).returns("enrolled")

      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

      # There are no PRs, so no analyses.
      assert_equal "not_enrolled", @private_org_repo.code_scanning_review_security_center_status.scanning_status
    end

    test "returns 'not_enrolled' if code scanning has not been active on prs within the last six hours" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.enable_advanced_security!(actor: @user)

      Repository.any_instance.expects(:code_scanning_security_center_scanning_status).returns("enrolled")

      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)

      create(:commit,
        repository: @private_org_repo,
        author: @user,
        branch: "cr-line-endings",
        changes: -> (files) {
          files.add("hello.rb", "puts 'Test'")
        }
      )

      old_pr = create(:pull_request,
        repository: @private_org_repo,
        base_user: @user,
        head_user: @user,
        base_ref: @private_org_repo.default_branch,
        head_ref: "cr-line-endings",
        user: @user,
        created_at: 2.days.ago,
      )
      old_pr.close(@user)

      pr = create(:pull_request,
        repository: @private_org_repo,
        base_user: @user,
        head_user: @user,
        base_ref: @private_org_repo.default_branch,
        head_ref: "cr-line-endings",
        user: @user,
        created_at: 1.day.ago,
      )

      GitHub::Turboscan.expects(:analyses).at_least_once.with(
        repository_id: @private_org_repo.id,
        ref_names_bytes: ["refs/pull/#{pr.number}/merge".b, "refs/pull/#{pr.number}/head".b, "refs/heads/cr-line-endings"],
      ).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::AnalysesResponse.new(
            {
              analyses: [],
              total_count: 0,
              complete_analysis_exists: false,
            }
          )
        )
      )

      assert_equal "not_enrolled", @private_org_repo.code_scanning_review_security_center_status.scanning_status
    end
  end

  context "code_scanning_open_alerts_count" do
    test "returns the number of open code scanning alerts" do
      with_cache_enabled do
        open_count = Turbocassette.use("code-scanning/index") do
          @private_org_repo.code_scanning_open_alerts_count
        end

        assert_equal 8, open_count
      end
    end

    test "memoizes the count returned from turboscan" do
      GitHub::Turboscan.expects(:counts).once.with(has_entry(repository_id: @private_org_repo.id)).returns(nil)

      assert_equal -1, @private_org_repo.code_scanning_open_alerts_count
      assert_equal -1, @private_org_repo.code_scanning_open_alerts_count
    end

    test "caches the count returned from turboscan accross requests" do
      same_repo = Repositories::Public.find_active!(@private_org_repo.id)

      with_cache_enabled do
        Turbocassette.use("code-scanning/index") do
          assert_equal 8, @private_org_repo.code_scanning_open_alerts_count
        end
        assert_equal 8, same_repo.code_scanning_open_alerts_count, "it should not hit turboscan again"
      end
    end

    test "caches the count if it is present" do
      same_repo = Repositories::Public.find_active!(@public_org_repo.id)

      with_cache_enabled do
        Turbocassette.use("code-scanning/index-turboscan-error") do
          assert_equal -1, @public_org_repo.code_scanning_open_alerts_count
        end
        Turbocassette.use("code-scanning/index") do
          assert_equal 8, same_repo.code_scanning_open_alerts_count
        end
        assert_equal 8, same_repo.code_scanning_open_alerts_count

        # We reload the model here, as in the same request the `nil` response would
        # still get memoized to avoid hitting the api more than once within the same
        # request
        assert_equal 8, Repositories::Public.find_active!(@public_org_repo.id).code_scanning_open_alerts_count
      end
    end

    test "uses different caches for different repos" do
      with_cache_enabled do
        Turbocassette.use("code-scanning/index-no-results") do
          assert_equal 0, @public_org_repo.code_scanning_open_alerts_count
        end
        Turbocassette.use("code-scanning/index") do
          assert_equal 8, @private_org_repo.code_scanning_open_alerts_count
        end
      end
    end
  end

  context "code_scanning_tool_names" do
    test "uses different caches for different repos" do
      with_cache_enabled do
        Turbocassette.use("code-scanning/index-no-results") do
          assert_equal [], @public_org_repo.code_scanning_tool_names
        end
        expected_tools = ["CodeQL",
           "Some other tool",
           "Different tool"]
        Turbocassette.use("code-scanning/index") do
          assert_equal expected_tools, @private_org_repo.code_scanning_tool_names
        end
      end
    end

    test "caches the values" do
      tools = %w[foo bar baz]
      GitHub::Turboscan.expects(:tool_names).once.with(has_entry(repository_id: @public_org_repo.id)).returns(tools)

      with_cache_enabled do
        3.times do
          assert_equal tools, Repositories::Public.find_active!(@public_org_repo.id).code_scanning_tool_names
        end
      end
    end
  end

  context "protected_branches_for_code_scanning_workflow" do
    test "? substitution" do
      repo = create(:repository, :minimal, owner: @org)
      create(:protected_branch, repository: repo, name: "protected1")
      create(:protected_branch, repository: repo, name: "protected?")
      create(:protected_branch, repository: repo, name: "protected???")

      # The default branch isn't protected, so exclude_default_branch has no effect
      # but we have to pass something
      branches = repo.protected_branches_for_code_scanning_workflow(exclude_default_branch: false)

      assert_equal 3, branches.length
      assert_equal "\"protected1\"", branches[0]
      assert_equal "\"protected[a-zA-Z0-9]\"", branches[1]
      assert_equal "\"protected[a-zA-Z0-9][a-zA-Z0-9][a-zA-Z0-9]\"", branches[2]
    end

    test "can exclude default branch even if that's protected" do
      repo = create(:repository, :minimal, owner: @org)

      # unprotected default branch is never included
      assert_empty repo.protected_branches_for_code_scanning_workflow(exclude_default_branch: true)
      assert_empty repo.protected_branches_for_code_scanning_workflow(exclude_default_branch: false)

      create(:protected_branch, repository: repo, name: repo.default_branch)
      repo.reload

      # protected default branch can be included
      assert_empty repo.protected_branches_for_code_scanning_workflow(exclude_default_branch: true)
      refute_empty repo.protected_branches_for_code_scanning_workflow(exclude_default_branch: false)

      branches = repo.protected_branches_for_code_scanning_workflow(exclude_default_branch: false)
      assert_equal 1, branches.length
      assert_equal "\"#{repo.default_branch}\"", branches[0]
    end
  end

  context "detected_codeql_languages_string" do
    test "sets correct list of supported languages" do
      repo = create(:repository, :minimal, owner: @org)

      repo.language_analysis.stubs(:language_percentages).returns([["C", 1], ["Foobar", 1], ["C++", 1], ["JavaScript", 1]])
      assert_equal "'c-cpp', 'javascript-typescript'", repo.detected_codeql_languages_string
    end
  end


  context "detected_codeql_languages_build_mapping" do
    test "returns a mapping from lang to build mode" do
      repo = create(:repository, :minimal, owner: @org)
      repo.language_analysis.stubs(:language_percentages).returns([["C", 1], ["Foobar", 1], ["C++", 1], ["JavaScript", 1]])

      build_mapping = repo.detected_codeql_languages_build_mapping
      assert_equal 2, build_mapping.length
      assert_equal "autobuild", build_mapping[:"c-cpp"]
      assert_equal "none", build_mapping[:"javascript-typescript"]
    end

    test "returns buildless for Java" do
      repo = create(:repository, :minimal, owner: @org)
      repo.language_analysis.stubs(:language_percentages).returns([["Java", 1]])

      build_mode = repo.detected_codeql_languages_build_mapping[:"java-kotlin"]
      assert_equal "none # This mode only analyzes Java. Set this to 'autobuild' or 'manual' to analyze Kotlin too.", build_mode
    end

    test "returns autobuild for Java + Kotlin" do
      repo = create(:repository, :minimal, owner: @org)
      repo.language_analysis.stubs(:language_percentages).returns([["Java", 1], ["Kotlin", 1]])

      assert_equal "autobuild", repo.detected_codeql_languages_build_mapping[:"java-kotlin"]
    end

    test "returns buildless for C#" do
      repo = create(:repository, :minimal, owner: @org)
      repo.language_analysis.stubs(:language_percentages).returns([["C#", 1]])

      assert_equal "none", repo.detected_codeql_languages_build_mapping[:csharp]
    end
  end


  context "refresh_code_scanning_status" do
    test "invalidate the count cache" do
      same_repo = Repositories::Public.find_active!(@private_org_repo.id)

      with_cache_enabled do
        Turbocassette.use("code-scanning/index") do
          assert_equal 8, @private_org_repo.code_scanning_open_alerts_count
        end
        Turbocassette.use("code-scanning/index-no-results") do
          assert_equal 8, Repositories::Public.find_active!(@private_org_repo.id).code_scanning_open_alerts_count
          @private_org_repo.refresh_code_scanning_status(alert_numbers: [])
          assert_equal 0, Repositories::Public.find_active!(@private_org_repo.id).code_scanning_open_alerts_count
        end
        assert_equal 0, Repositories::Public.find_active!(@private_org_repo.id).code_scanning_open_alerts_count
      end
    end
  end

  %w[
    cpp_dependency_installation
    default_codeql_version_2_18_4
    default_codeql_version_2_19_0
    default_codeql_version_2_19_1
    default_codeql_version_2_19_2
    default_codeql_version_2_19_3
    default_codeql_version_2_19_4
    default_codeql_version_2_19_5
    default_codeql_version_2_19_6
    disable_java_buildless
    disable_kotlin_analysis
    export_diagnostics
    qa_telemetry
  ].each do |feature|
    enablement_method_name = "code_scanning_#{feature}_enabled?"
    enabled_flipper = "code_scanning_#{feature}"
    disabled_flipper = "#{enabled_flipper}_disabled"

    context "##{enablement_method_name}" do
      test "returns true when globally enabled and not disabled" do
        GitHub.flipper[enabled_flipper].enable
        GitHub.flipper[disabled_flipper].disable
        assert @private_org_repo.method(enablement_method_name).call
      end

      test "returns true when enabled for repo and not disabled" do
        GitHub.flipper[enabled_flipper].enable(@private_org_repo)
        GitHub.flipper[disabled_flipper].disable
        assert @private_org_repo.method(enablement_method_name).call
      end

      test "returns true when enabled for org and not disabled" do
        GitHub.flipper[enabled_flipper].enable(@org)
        GitHub.flipper[disabled_flipper].disable
        assert @private_org_repo.method(enablement_method_name).call
      end

      # Skip GHES since there can only be one business on GHES
      test "returns true when enabled for business and not disabled", skip_enterprise: true do
        business = create(:business)
        org = create(:organization, business: business)
        repo = create(:private_repository, :minimal, owner: org)

        GitHub.flipper[enabled_flipper].enable(business)
        GitHub.flipper[disabled_flipper].disable
        assert repo.method(enablement_method_name).call
      end

      test "returns false when globally enabled but disabled for repo" do
        GitHub.flipper[enabled_flipper].enable
        GitHub.flipper[disabled_flipper].enable(@private_org_repo)
        refute @private_org_repo.method(enablement_method_name).call
      end

      test "returns false when globally enabled but disabled for org" do
        GitHub.flipper[enabled_flipper].enable
        GitHub.flipper[disabled_flipper].enable(@org)
        refute @private_org_repo.method(enablement_method_name).call
      end

      test "returns false when enabled for org but disabled for repo" do
        GitHub.flipper[enabled_flipper].enable(@org)
        GitHub.flipper[disabled_flipper].enable(@private_org_repo)
        refute @private_org_repo.method(enablement_method_name).call
      end

      test "returns false when enabled for repo but disabled for org" do
        GitHub.flipper[enabled_flipper].enable(@private_org_repo)
        GitHub.flipper[disabled_flipper].enable(@org)
        refute @private_org_repo.method(enablement_method_name).call
      end

      # Skip GHES since there can only be one business on GHES
      test "returns false when enabled for repo but disabled for business", skip_enterprise: true do
        business = create(:business)
        org = create(:organization, business: business)
        repo = create(:private_repository, :minimal, owner: org)

        GitHub.flipper[enabled_flipper].enable(repo)
        GitHub.flipper[disabled_flipper].enable(business)
        refute repo.method(enablement_method_name).call
      end
    end
  end

  context "#code_scanning_readable_by" do
    test "returns false when code scanning is disabled" do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(false)
      refute @private_org_repo.code_scanning_readable_by?(@user)
      refute @public_org_repo.code_scanning_readable_by?(@user)
      refute @private_user_repo.code_scanning_readable_by?(@user)
      refute @public_user_repo.code_scanning_readable_by?(@user)
      refute @private_org_repo.code_scanning_readable_by?(@staff_user)
      refute @public_org_repo.code_scanning_readable_by?(@staff_user)
      refute @private_user_repo.code_scanning_readable_by?(@staff_user)
      refute @public_user_repo.code_scanning_readable_by?(@staff_user)
    end

    test "returns true when a user is an admin on a repo" do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      assert @private_org_repo.code_scanning_readable_by?(@user)
      assert @public_org_repo.code_scanning_readable_by?(@user)
      assert @private_user_repo.code_scanning_readable_by?(@user)
      assert @public_user_repo.code_scanning_readable_by?(@user)
    end

    test "returns false when user is not an admin" do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      new_user = create(:user)
      refute @private_org_repo.code_scanning_readable_by?(new_user)
      refute @public_org_repo.code_scanning_readable_by?(new_user)
      refute @private_user_repo.code_scanning_readable_by?(new_user)
      refute @public_user_repo.code_scanning_readable_by?(new_user)
    end

    test "returns true on dotcom when user is staff and has read access to a rep", skip_enterprise: true do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      refute @private_org_repo.code_scanning_readable_by?(@staff_user)
      assert @public_org_repo.code_scanning_readable_by?(@staff_user)
      refute @private_user_repo.code_scanning_readable_by?(@staff_user)
      assert @public_user_repo.code_scanning_readable_by?(@staff_user)
    end

    test "returns false on enterprise when user is staff and is not admin on a repo", enterprise_only: true do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      refute @private_org_repo.code_scanning_readable_by?(@staff_user)
      refute @public_org_repo.code_scanning_readable_by?(@staff_user)
      refute @private_user_repo.code_scanning_readable_by?(@staff_user)
      refute @public_user_repo.code_scanning_readable_by?(@staff_user)
    end
  end

  context "#code_scanning_readable_because_hubber?" do
    test "returns false when code scanning is disabled" do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(false)
      refute @private_org_repo.code_scanning_readable_because_hubber?(@user)
      refute @public_org_repo.code_scanning_readable_because_hubber?(@user)
      refute @private_user_repo.code_scanning_readable_because_hubber?(@user)
      refute @public_user_repo.code_scanning_readable_because_hubber?(@user)
      refute @private_org_repo.code_scanning_readable_because_hubber?(@staff_user)
      refute @public_org_repo.code_scanning_readable_because_hubber?(@staff_user)
      refute @private_user_repo.code_scanning_readable_because_hubber?(@staff_user)
      refute @public_user_repo.code_scanning_readable_because_hubber?(@staff_user)
    end

    test "returns false for a non-staff user that is an admin on a repo" do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      refute @private_org_repo.code_scanning_readable_because_hubber?(@user)
      refute @public_org_repo.code_scanning_readable_because_hubber?(@user)
      refute @private_user_repo.code_scanning_readable_because_hubber?(@user)
      refute @public_user_repo.code_scanning_readable_because_hubber?(@user)
    end

    test "returns false for a non-staff user that is not an admin on a repo" do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      new_user = create(:user)
      refute @private_org_repo.code_scanning_readable_because_hubber?(new_user)
      refute @public_org_repo.code_scanning_readable_because_hubber?(new_user)
      refute @private_user_repo.code_scanning_readable_because_hubber?(new_user)
      refute @public_user_repo.code_scanning_readable_because_hubber?(new_user)
    end

    test "returns true on dotcom when user is staff and has read access to a rep", skip_enterprise: true do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      refute @private_org_repo.code_scanning_readable_because_hubber?(@staff_user)
      assert @public_org_repo.code_scanning_readable_because_hubber?(@staff_user)
      refute @private_user_repo.code_scanning_readable_because_hubber?(@staff_user)
      assert @public_user_repo.code_scanning_readable_because_hubber?(@staff_user)
    end

    test "returns false on enterprise when user is staff and is not admin on a repo", enterprise_only: true do
      Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      refute @private_org_repo.code_scanning_readable_because_hubber?(@staff_user)
      refute @public_org_repo.code_scanning_readable_because_hubber?(@staff_user)
      refute @private_user_repo.code_scanning_readable_because_hubber?(@staff_user)
      refute @public_user_repo.code_scanning_readable_because_hubber?(@staff_user)
    end
  end

  context "#show_code_scanning_workflows_in_actions?", skip_enterprise: true do
    test "returns true for everything but private user repos when config flag is true" do
      GitHub.stubs(:code_scanning_enabled?).returns(false)
      refute @public_org_repo.show_code_scanning_workflows_in_actions?
      refute @private_org_repo.show_code_scanning_workflows_in_actions?
      refute @public_user_repo.show_code_scanning_workflows_in_actions?
      refute @private_user_repo.show_code_scanning_workflows_in_actions?

      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      assert @public_org_repo.show_code_scanning_workflows_in_actions?
      assert @private_org_repo.show_code_scanning_workflows_in_actions?
      assert @public_user_repo.show_code_scanning_workflows_in_actions?
      refute @private_user_repo.show_code_scanning_workflows_in_actions?

      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      assert @public_org_repo.show_code_scanning_workflows_in_actions?
      assert @private_org_repo.show_code_scanning_workflows_in_actions?
      assert @public_user_repo.show_code_scanning_workflows_in_actions?
      refute @private_user_repo.show_code_scanning_workflows_in_actions?
    end

    test "returns false if code scanning is banned even if Code Scanning and GHAS marked as enabled" do
      Repository.any_instance.stubs(:code_scanning_banned?).returns(true)
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      refute @public_user_repo.show_code_scanning_workflows_in_actions?
      refute @public_org_repo.show_code_scanning_workflows_in_actions?
      refute @private_user_repo.show_code_scanning_workflows_in_actions?
      refute @private_org_repo.show_code_scanning_workflows_in_actions?
    end

    test "returns true if org private repos advanced security purchased but Code Scanning not enabled" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      refute @private_org_repo.code_scanning_enabled?
      assert @private_org_repo.show_code_scanning_workflows_in_actions?
    end

    test "returns true for org private repos even if advanced security is not purchased" do
      @org.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      refute @private_org_repo.code_scanning_enabled?
      assert @private_org_repo.show_code_scanning_workflows_in_actions?
    end
  end

  context "#show_code_scanning_workflows_in_actions? on enterprise", enterprise_only: true do
    test "returns true for org repos only when config flag and license field are true" do
      GitHub::Enterprise.ensure_business!
      @public_org_repo.enable_advanced_security!(actor: @user)

      GitHub.stubs(:code_scanning_enabled?).returns(false)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      refute @public_org_repo.show_code_scanning_workflows_in_actions?
      refute @private_org_repo.show_code_scanning_workflows_in_actions?

      GitHub.stubs(:code_scanning_enabled?).returns(false)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      refute @public_org_repo.show_code_scanning_workflows_in_actions?
      refute @private_org_repo.show_code_scanning_workflows_in_actions?

      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      refute @public_org_repo.show_code_scanning_workflows_in_actions?
      refute @private_org_repo.show_code_scanning_workflows_in_actions?

      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      assert @public_org_repo.show_code_scanning_workflows_in_actions?
      assert @private_org_repo.show_code_scanning_workflows_in_actions?
    end

    test "returns false for personal private and public repos even if config and license field are true" do
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)

      refute @private_user_repo.show_code_scanning_workflows_in_actions?
      refute @public_user_repo.show_code_scanning_workflows_in_actions?
    end

    test "returns true if advanced security purchased but Code Scanning not enabled on repo" do
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)

      refute @private_org_repo.code_scanning_enabled?
      assert @private_org_repo.show_code_scanning_workflows_in_actions?
    end
  end

  context "code_scanning_enterprise_disabled?" do
    test "returns false on GitHub Enterprise Server", enterprise_only: true do
      refute @private_special_disabled_org_repo.code_scanning_enterprise_disabled?
    end

    test "returns true on GitHub Enterprise Server for user repos", enterprise_only: true do
      assert @private_user_repo.code_scanning_enterprise_disabled?
      assert @public_user_repo.code_scanning_enterprise_disabled?
    end

    test "returns true if the repository is owned by an EMU account", skip_enterprise: true do
      owner = create(:user)
      business = create(:business, :enterprise_managed)
      business.mark_advanced_security_as_purchased_for_entity(actor: owner)

      # EMU
      emu_user = create(:emu, business: business)
      emu_owned_repo = create(:private_repository, force_user_owned: true, owner: emu_user)

      assert emu_owned_repo.code_scanning_enterprise_disabled?
    end

    test "returns true if repository is private and enterprise is specially disabled", skip_enterprise: true do
      assert @private_special_disabled_org_repo.code_scanning_enterprise_disabled?
    end

    test "returns false if repository is public and enterprise is specially disabled" do
      refute @public_special_disabled_org_repo.code_scanning_enterprise_disabled?
    end

    test "returns false for repository that is not part of an enterprise" do
      refute @private_org_repo.code_scanning_enterprise_disabled?
    end
  end

  context "severities" do
    test "returns severities for the repository" do
      GitHub::Turboscan
        .expects(:severities_for_org)
        .once
        .with({
          repository_ids: [@private_org_repo.id],
          filter: Turboscan::Proto::AlertsFilter.new(state: GitHub::Turboscan.to_alert_state_filter("open")).to_h,
          excluded_repository_ids: [],
          owner_ids: [@org.id],
        })
        .returns(
          Twirp::ClientResp.new(
            data: Turboscan::Proto::SeveritiesForOrgResponse.new(
              severities: [
                Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 1, severity: ::Turboscan::Proto::Severity::SEVERITY_LOW),
                Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem.new(alert_count: 2, severity: ::Turboscan::Proto::Severity::SEVERITY_HIGH)
              ]
            )
          )
        )
      severities = @private_org_repo.code_scanning_open_alerts_count_by_severity
      assert_equal({ "low" => 1, "high" => 2 }, severities)
    end

    test "returns no severities for the repository" do
      GitHub::Turboscan
        .expects(:severities_for_org)
        .once
        .with({
          repository_ids: [@private_org_repo.id],
          filter: Turboscan::Proto::AlertsFilter.new(state: GitHub::Turboscan.to_alert_state_filter("open")).to_h,
          excluded_repository_ids: [],
          owner_ids: [@org.id],
        })
        .returns(
          Twirp::ClientResp.new(
            data: Turboscan::Proto::SeveritiesForOrgResponse.new
          )
        )
      severities = @private_org_repo.code_scanning_open_alerts_count_by_severity
      assert_equal({}, severities)
    end

    test "returns nil for the repository on error" do
      GitHub::Turboscan
        .expects(:severities_for_org)
        .once
        .with({
          repository_ids: [@private_org_repo.id],
          filter: Turboscan::Proto::AlertsFilter.new(state: GitHub::Turboscan.to_alert_state_filter("open")).to_h,
          excluded_repository_ids: [],
          owner_ids: [@org.id],
        })
        .returns(Twirp::ClientResp.new(error: Twirp::Error.new(:internal, "something went wrong")))

      severities = @private_org_repo.code_scanning_open_alerts_count_by_severity
      assert_nil(severities)
    end
  end
end
