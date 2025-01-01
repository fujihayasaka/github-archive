# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/innersource_helper"

class RepositoryAdvisoryTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include InnersourceHelper
  include StringFromBinaryTestHelper
  include HydroMessageJobTestHelpers

  fixtures do
    @admin = create(:paid_user)
    @org   = create(:business_organization, login: "acme", admin: @admin)
    @repo  = create(:repository, name: "public-test", owner: @org, from_example: :pull_request_source)
    @team  = create(:team, organization: @org)

    @author = create(:user, login: "author")
    @publisher = create(:user, login: "publisher")
    @collab = create(:user, login: "collab")
    @rando = create(:user, login: "Random-user")

    @integration = create :integration
    @installation = make_integration_installation integration: @integration, target: @repo.owner, permissions: { "repository_advisories" => :write }

    description = <<~MD
      **Urgent**: Vulnerability has been _disclosed_ 😱

      [Read more here](https://example.com/oh-noes)
    MD

    @advisory = create(:repository_advisory,
                        repository: @repo,
                        author: @author,
                        title: "💎 Path Traversal on Default Installed Rails Application",
                        description: description,
                        cve_id: "CVE-1900-0001",
                        severity: "moderate",
                        created_at: 1.minute.ago)
    @advisory.affected_products.first.update!(
      package: "my-example-package.rb",
      ecosystem: "RubyGems",
      affected_versions: "<5.1.0",
      patches: "No patches currently available.",
    )

    Timecop.freeze(@advisory.created_at + 5.seconds) { @advisory.add_collaborator(@collab) }
    Timecop.freeze(@advisory.created_at + 10.seconds) { @advisory.add_collaborator(@team) }
    Timecop.freeze(@advisory.created_at + 15.seconds) { @advisory.create_comment(@collab, "A comment") }
    Timecop.freeze(@advisory.created_at + 20.seconds) { @advisory.create_comment(@collab, "A comment") }

    Timecop.freeze(@advisory.created_at + 25.seconds) do
      @advisory_credit = create(:advisory_credit,
        repository_advisory: @advisory,
        recipient: @collab,
        creator: @admin)
    end

    GitHub.context.push(actor_id: @admin.id)
    @workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @admin)
    @workspace_repo.save!
    example_repo :pull_request_fork, @workspace_repo

    @workspace_pull1 = create :pull_request,
      issue: create(:issue, repository: @workspace_repo, user: @admin),
      base_repository: @advisory.repository,
      head_repository: @workspace_repo,
      base_ref: "master-forward-2",
      head_ref: "topic"
    @workspace_pull2 = create :pull_request,
      issue: create(:issue, repository: @workspace_repo, user: @admin),
      base_repository: @advisory.repository,
      head_repository: @workspace_repo,
      base_ref: "master",
      head_ref: "master-plus-one-commit"

    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager = create(:user)
    @security_manager_team.add_member(@security_manager)
  end

  context "validation" do
    test "an draft advisory with only title and description is valid" do
      repo = create :repository
      author = create :user
      advisory = RepositoryAdvisory.new repository: repo, author: author
      refute advisory.valid?
      advisory.title = "test title"
      advisory.description = "test description"
      assert advisory.valid?
      assert advisory.save
    end

    test "a draft advisory cannot be published with only whitespace description changes from the description template" do
      advisory = create(:draft_repository_advisory,
        title: "Test title",
        description: "Test description",
        cve_id: "CVE-1900-0001",
        severity: "moderate",
        created_at: 1.minute.ago)

      assert advisory.publishable?

      advisory.description = RepositoryAdvisory.description_template + "\r\n "

      refute advisory.publishable?
    end

    test "an advisory is invalid without a repository" do
      assert @advisory.valid?
      @advisory.repository = nil
      refute @advisory.valid?
    end

    test "an advisory is invalid without an author" do
      assert @advisory.valid?
      @advisory.author = nil
      refute @advisory.valid?
    end

    test "an advisory is invalid without a title" do
      assert @advisory.valid?
      @advisory.title = nil
      refute @advisory.valid?
    end

    %w{
      open
      closed
      published
    }.each do |state|
      test "an advisory is valid with a state of #{state}" do
        assert @advisory.valid?
        @advisory.state = state
        assert @advisory.valid?
      end
    end

    test "an advisory is invalid with an incorrect state" do
      assert @advisory.valid?
      assert_raises ArgumentError do
        @advisory.state = "teapot"
      end
    end

    %w{
      low
      moderate
      high
      critical
    }.each do |severity|
      test "an advisory is valid with a severity of #{severity}" do
        assert @advisory.valid?
        @advisory.severity = severity
        assert @advisory.valid?
      end
    end

    test "an advisory is invalid with an incorrect severity" do
      assert @advisory.valid?
      assert_raises ArgumentError do
        @advisory.severity = "spicy"
      end
    end

    test "an advisory is valid with a correct cve_id" do
      assert @advisory.valid?
      @advisory.cve_id = "CVE-1900-0001"
      assert @advisory.valid?
    end

    test "an advisory is invalid with a malformed cve_id" do
      assert @advisory.valid?
      @advisory.cve_id = "CWE-0000-001"
      refute @advisory.valid?
    end

    test "advisory cve_id error correctly uses 'CVE identifier' when invalid" do
      assert @advisory.valid?
      @advisory.cve_id = "None"
      refute @advisory.valid?
      assert_equal "CVE identifier is invalid", @advisory.errors.full_messages.first
    end

    test "cvss_v3 is an optional field" do
      repository_advisory = build(:repository_advisory, cvss_v3: nil)

      repository_advisory.save!
    end

    test "cvss_v4 is an optional field" do
      repository_advisory = build(:repository_advisory, cvss_v4: nil)

      repository_advisory.save!
    end

    test "cvss_v3 must have at least 8 key-value metric pairs and at most 22 pairs" do
      repository_advisory = build(:repository_advisory)

      repository_advisory.cvss_v3 = "CVSS:3.0/AV:L/AC:L/PR:N/UI:N/S:U/C:L/I:H"
      refute repository_advisory.valid?

      repository_advisory.cvss_v3 = "CVSS:3.0/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:L/E:U/RL:T/RC:U/CR:X/IR:M/AR:X/MAV:P/MAC:L/MPR:N/MUI:N/MS:U/MC:X/MI:H/MA:X/MA:X"
      refute repository_advisory.valid?
    end

    test "cvss_v4 must have at least 11 key-value metric pairs and at most 26 pairs" do
      repository_advisory = build(:repository_advisory)

      repository_advisory.cvss_v4 = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N"
      refute repository_advisory.valid?

      repository_advisory.cvss_v4 = "CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H/MAV:N/MAC:H/MAT:N/MPR:L/MUI:N/MVC:H/MVI:H/MVA:H/MSC:H/MSI:S/MSA:H/CR:M/IR:H/AR:M/E:P/MSC:H"
      refute repository_advisory.valid?
    end

    test "cvss_v3 must obey the CVSS V3 format" do
      cvss_v3 = "abcdefghijklmnopqrstuvwxyz0123456789"
      repository_advisory = build(:repository_advisory, cvss_v3: cvss_v3)
      refute repository_advisory.save

      repository_advisory.cvss_v3 = "CVSS:2.0/AV:L/AC:L/PR:N/UI:N/S:U/C:N"
      refute repository_advisory.save
    end

    test "cvss_v4 must obey the CVSS V4 format" do
      cvss_v4 = "abcdefghijklmnopqrstuvwxyz0123456789"
      repository_advisory = build(:repository_advisory, cvss_v3: cvss_v4)
      refute repository_advisory.save

      repository_advisory.cvss_v4 = "CVSS:2.0/AV:L/AC:L/PR:N/UI:N/S:U/C:N"
      refute repository_advisory.save
    end

    test "cvss_v3 does not accept a vector string that obeys the format, but has invalid key-value pairs" do
      # PR:X is an invalid pair.
      cvss_v3 = "CVSS:3.1/AV:L/AC:L/PR:X/UI:N/S:U/C:L/I:H/A:H"
      repository_advisory = build(:repository_advisory, cvss_v3: cvss_v3)
      refute_predicate repository_advisory, :valid?
    end

    test "cvss_v4 does not accept a vector string that obeys the format, but has invalid key-value pairs" do
      # U:T is an invalid pair.
      cvss_v4 = "CVSS:4.0/AV:P/AC:L/U:T/PR:L/UI:N/VC:L/VI:L/VA:L/SC:L/SI:L/SA:L"
      repository_advisory = build(:repository_advisory, cvss_v4: cvss_v4)
      refute_predicate repository_advisory, :valid?
    end

    test "cvss_v3 cannot include emoji characters" do
      cvss_v3 = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:H/A:N/E:P/RL:T/RC:C/CR:L/IR:L/AR:L/MAV:N/MAC:L/MPR:L/MUI:N/MS:C/MC:L/MI:⭐️"
      repository_advisory = build(:repository_advisory, cvss_v3: cvss_v3)

      refute repository_advisory.save
    end

    test "cvss_v3 accepts the CVSS v3.0 format" do
      cvss_v3 = "CVSS:3.0/AV:L/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N/E:P/RL:T/RC:U/CR:L/IR:H/AR:H/MAV:L/MAC:L/MPR:L/MUI:N/MS:U/MC:L/MI:N/MA:H"
      repository_advisory = build(:repository_advisory, cvss_v3: cvss_v3)

      repository_advisory.save!
    end

    test "cvss_v3 accepts the CVSS v3.1 format" do
      cvss_v3 = "CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N/E:P/RL:T/RC:U/CR:L/IR:H/AR:H/MAV:L/MAC:L/MPR:L/MUI:N/MS:U/MC:L/MI:N/MA:H"
      repository_advisory = build(:repository_advisory, cvss_v3: cvss_v3)

      repository_advisory.save!
    end

    test "does not allow to set cvss_v4 and cvss_v3 together" do
      cvss_v3 = "CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:L/I:L/A:N"
      cvss_v4 = "CVSS:4.0/AV:P/AC:L/AT:P/PR:L/UI:N/VC:L/VI:L/VA:L/SC:L/SI:L/SA:L"

      repository_advisory = build(:repository_advisory, cvss_v3: cvss_v3, cvss_v4: cvss_v4)
      refute repository_advisory.save
      assert_equal "Only one CVSS vector can be saved", repository_advisory.errors.full_messages.first
    end
  end

  test "can create an advisory with all user editable text fields set to utf-8 strings" do
    refute_nil create(:repository_advisory, :all_user_editable_text_fields_contain_utf)
  end

  test "global relay id encodes the ghsa_id" do
    decoded_global_id = Platform::Helpers::NodeIdentification.from_global_id(@advisory.global_relay_id)

    assert_equal decoded_global_id, ["RepositoryAdvisory", @advisory.ghsa_id]
  end

  test "should remove the cvss_v3 if cvss_v4 is set" do
    cvss_v3 = "CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:L/I:L/A:N"
    cvss_v4 = "CVSS:4.0/AV:P/AC:L/AT:P/PR:L/UI:N/VC:L/VI:L/VA:L/SC:L/SI:L/SA:L"

    repository_advisory = create(:repository_advisory, cvss_v3: cvss_v3)

    assert repository_advisory.save
    assert_equal repository_advisory.reload.cvss_v3, cvss_v3

    repository_advisory.update(cvss_v4: cvss_v4)
    assert_equal repository_advisory.reload.cvss_v4, cvss_v4
    assert_nil repository_advisory.cvss_v3
  end

  test "should remove the cvss_v4 if cvss_v3 is set" do
    cvss_v3 = "CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:L/I:L/A:N"
    cvss_v4 = "CVSS:4.0/AV:P/AC:L/AT:P/PR:L/UI:N/VC:L/VI:L/VA:L/SC:L/SI:L/SA:L"

    repository_advisory = create(:repository_advisory, cvss_v4: cvss_v4)

    assert repository_advisory.save
    assert_equal repository_advisory.reload.cvss_v4, cvss_v4

    repository_advisory.update(cvss_v3: cvss_v3)
    assert_equal repository_advisory.reload.cvss_v3, cvss_v3
    assert_nil repository_advisory.cvss_v4
  end

  test "#async_path_uri" do
    assert_equal "/acme/public-test/security/advisories/#{@advisory.ghsa_id}", @advisory.async_path_uri.sync.to_s
  end

  context "abilities" do
    test "#adminable_by? is only true for Repository admins regardless of Advisory state" do
      assert @advisory.adminable_by?(@admin)
      assert @advisory.adminable_by?(@security_manager)
      assert @advisory.adminable_by?(@installation)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.adminable_by?(@rando)

      @advisory.set_closed

      assert @advisory.adminable_by?(@admin)
      assert @advisory.adminable_by?(@security_manager)
      assert @advisory.adminable_by?(@installation)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.adminable_by?(@rando)

      @advisory.set_open
      @advisory.set_published

      assert @advisory.adminable_by?(@admin)
      assert @advisory.adminable_by?(@security_manager)
      assert @advisory.adminable_by?(@installation)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.adminable_by?(@rando)
    end

    test "#writable_by? is true for collaborators and Repository admins" do
      assert @advisory.writable_by?(@admin)
      assert @advisory.writable_by?(@security_manager)
      assert @advisory.writable_by?(@collab)
      assert @advisory.writable_by?(@installation)
      refute @advisory.writable_by?(@rando)

      @advisory.set_published

      assert @advisory.writable_by?(@admin)
      assert @advisory.writable_by?(@security_manager)
      assert @advisory.writable_by?(@collab)
      assert @advisory.writable_by?(@installation)
      refute @advisory.writable_by?(@rando)

      @advisory.set_closed

      assert @advisory.writable_by?(@admin)
      assert @advisory.writable_by?(@security_manager)
      assert @advisory.writable_by?(@collab)
      assert @advisory.writable_by?(@installation)
      refute @advisory.writable_by?(@rando)
    end

    test "#readable_by? is true for collaborators and Repository admins and PVD submitters unless published" do
      pvd_advisory = create(:pending_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      pvd_advisory.remove_collaborator(pvd_submitter)

      assert @advisory.readable_by?(@admin)
      assert @advisory.readable_by?(@security_manager)
      assert @advisory.readable_by?(@collab)
      assert @advisory.readable_by?(@installation)
      refute @advisory.readable_by?(@rando)
      assert pvd_advisory.readable_by?(pvd_submitter)

      @advisory.set_closed
      pvd_advisory.set_closed

      assert @advisory.readable_by?(@admin)
      assert @advisory.readable_by?(@security_manager)
      assert @advisory.readable_by?(@collab)
      assert @advisory.readable_by?(@installation)
      refute @advisory.readable_by?(@rando)
      assert pvd_advisory.readable_by?(pvd_submitter)

      @advisory.remove_collaborator(@collab)
      refute @advisory.readable_by?(@collab)
    end

    test "#readable_by? is true for everyone once published" do
      @advisory.set_published

      assert @advisory.readable_by?(@admin)
      assert @advisory.readable_by?(@security_manager)
      assert @advisory.readable_by?(@collab)
      assert @advisory.readable_by?(@rando)
      assert @advisory.readable_by?(@installation)
    end

    test "#writable_by? is false if a collaborator is removed" do
      assert @advisory.writable_by?(@collab)

      @advisory.remove_collaborator(@collab)

      refute @advisory.writable_by?(@collab)
    end

    test "all abilities are not cleaned up once published" do
      existing_abilities = Authorization.service.direct_abilities_on_subject(subject: @advisory)

      @advisory.set_published

      assert_equal existing_abilities, Authorization.service.direct_abilities_on_subject(subject: @advisory)
    end

    test "all abilities are cleaned up once destroyed" do
      refute_empty Authorization.service.direct_abilities_on_subject(subject: @advisory)

      perform_enqueued_jobs(only: [ClearAbilitiesJob]) do
        @advisory.destroy
      end

      assert_empty Authorization.service.direct_abilities_on_subject(subject: @advisory)
    end

    test "#viewer_can_update?, #viewer_can_delete? and viewer_can_read_user_content_edits? is true for collaborators and Repository admins" do
      valid_users = [@admin, @security_manager, @collab]
      invalid_users = [@rando]
      functions_to_test = [:viewer_can_update?, :viewer_can_delete?, :viewer_can_read_user_content_edits?]
      memoized_variables = [:@viewer_can_update, :@viewer_can_delete, :@viewer_can_read_user_content_edits]

      functions_to_test.zip(memoized_variables).each do |function, variable|
        # test the valid users
        valid_users.each do |user|
          assert @advisory.method(function).call(user), "#{function} should be true for #{user.login}"
          @advisory.remove_instance_variable(variable)
        end

        invalid_users.each do |user|
          refute @advisory.method(function).call(user), "#{function} should be false for #{user.login}"
          @advisory.remove_instance_variable(variable)
        end

        refute @advisory.method(function).call(nil)
      end
    end

    test "#unpublished_and_viewer_readable_only? is true for read-only collaborators on pending unpublished advisory" do
      pvd_advisory = create(:pending_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      pvd_advisory.remove_collaborator(pvd_submitter)

      refute pvd_advisory.accepted?
      assert pvd_advisory.readable_by?(pvd_submitter)
      refute pvd_advisory.writable_by?(pvd_submitter)
      assert pvd_advisory.unpublished_and_viewer_readable_only?(pvd_submitter)
    end

    test "#unpublished_and_viewer_readable_only? is true for read-only collaborators on accepted unpublished advisory" do
      pvd_advisory = create(:accepted_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      pvd_advisory.remove_collaborator(pvd_submitter)

      assert pvd_advisory.accepted?
      assert pvd_advisory.readable_by?(pvd_submitter)
      refute pvd_advisory.writable_by?(pvd_submitter)
      assert pvd_advisory.unpublished_and_viewer_readable_only?(pvd_submitter)
    end

    test "#unpublished_and_viewer_readable_only? is false for read-only collaborators if the advisory is published" do
      pvd_advisory = create(:accepted_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      repo_owner = pvd_advisory.repository.owner
      pvd_advisory.remove_collaborator(pvd_submitter)
      pvd_advisory.set_published(actor: repo_owner)

      assert pvd_advisory.published?
      assert pvd_advisory.readable_by?(pvd_submitter)
      refute pvd_advisory.writable_by?(pvd_submitter)
      refute pvd_advisory.unpublished_and_viewer_readable_only?(pvd_submitter)
    end

    test "#unpublished_and_viewer_readable_only? is false for full access collaborators and repository admins on unpublished advisory" do
      pvd_advisory = create(:accepted_pvd_repo_advisory)
      repo_owner = pvd_advisory.repository.owner

      refute pvd_advisory.published?
      assert pvd_advisory.writable_by?(repo_owner)
      refute pvd_advisory.unpublished_and_viewer_readable_only?(repo_owner)
    end

    test "#unpublished_and_viewer_readable_only? is false for full access collaborators and repository admins on published advisory" do
      pvd_advisory = create(:published_pvd_repo_advisory)
      repo_owner = pvd_advisory.repository.owner

      assert pvd_advisory.published?
      assert pvd_advisory.writable_by?(repo_owner)
      refute pvd_advisory.unpublished_and_viewer_readable_only?(repo_owner)
    end
  end

  context "#api_scope" do
    test "Returns correctly for open source advisories" do
      assert_equal @advisory.api_scope, "open_source"
    end

    test "Returns correctly for innersource advisories" do
      enable_innersource
      assert_equal @advisory.api_scope, "innersource"
    end
  end

  context "#get_title and #get_description" do
    test "returns frozen title and description for removed PVD author" do
      pvd_advisory = create(:accepted_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      pvd_advisory.remove_collaborator(pvd_submitter)

      updated_title = pvd_advisory.title + " (updated)"
      updated_description = pvd_advisory.description + " (updated)"
      pvd_advisory.update(title: updated_title, description: updated_description)

      assert_equal pvd_advisory.get_title(pvd_submitter), pvd_advisory.frozen_title
      refute_equal pvd_advisory.get_title(pvd_submitter), pvd_advisory.title

      assert_equal pvd_advisory.get_description(pvd_submitter), pvd_advisory.frozen_description
      refute_equal pvd_advisory.get_description(pvd_submitter), pvd_advisory.description
    end

    test "returns current title and description for full collaborator" do
      pvd_advisory = create(:accepted_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      repo_owner = pvd_advisory.repository.owner
      pvd_advisory.remove_collaborator(pvd_submitter)

      updated_title = pvd_advisory.title + " (updated)"
      updated_description = pvd_advisory.description + " (updated)"
      pvd_advisory.update(title: updated_title, description: updated_description)

      assert_equal pvd_advisory.get_title(repo_owner), pvd_advisory.title
      refute_equal pvd_advisory.get_title(repo_owner), pvd_advisory.frozen_title

      assert_equal pvd_advisory.get_description(repo_owner), pvd_advisory.description
      refute_equal pvd_advisory.get_description(repo_owner), pvd_advisory.frozen_description
    end

    test "returns frozen title/description if no viewer is given and frozen title/description exists for an unpublished advisory" do
      pvd_advisory = create(:accepted_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      pvd_advisory.remove_collaborator(pvd_submitter)

      updated_title = pvd_advisory.title + " (updated)"
      updated_description = pvd_advisory.description + " (updated)"
      pvd_advisory.update(title: updated_title, description: updated_description)

      assert_equal pvd_advisory.get_title(nil), pvd_advisory.frozen_title
      refute_equal pvd_advisory.get_title(nil), pvd_advisory.title

      assert_equal pvd_advisory.get_description(nil), pvd_advisory.frozen_description
      refute_equal pvd_advisory.get_description(nil), pvd_advisory.description
    end

    test "returns current title/description if no viewer is given and frozen title/description exists for a published advisory" do
      pvd_advisory = create(:published_pvd_repo_advisory)
      pvd_submitter = pvd_advisory.author
      pvd_advisory.remove_collaborator(pvd_submitter)

      updated_title = pvd_advisory.title + " (updated)"
      updated_description = pvd_advisory.description + " (updated)"
      pvd_advisory.update(title: updated_title, description: updated_description)

      assert_equal pvd_advisory.get_title(nil), pvd_advisory.title
      refute_equal pvd_advisory.get_title(nil), pvd_advisory.frozen_title

      assert_equal pvd_advisory.get_description(nil), pvd_advisory.description
      refute_equal pvd_advisory.get_description(nil), pvd_advisory.frozen_description
    end

    test "returns current title/description if no viewer is given and frozen title/description does not exist" do
      pvd_advisory = create(:accepted_pvd_repo_advisory)

      title = "big issue!"
      pvd_advisory.update(title: title)

      assert pvd_advisory.frozen_title.nil?
      assert_equal pvd_advisory.get_title(nil), pvd_advisory.title

      assert pvd_advisory.frozen_description.nil?
      assert_equal pvd_advisory.get_description(nil), pvd_advisory.description
    end
  end

  context "#type" do
    test "advisories opened from open source repos are of type 'open_source'" do
      open_org = create(:organization)
      public_repo = create(:public_repository, owner: open_org)
      new_advisory = create(:repository_advisory, repository: public_repo)
      assert_equal new_advisory.repo_advisory_type, "open_source"
    end

    test "advisories opened from innersourced repos are of type 'inner_source'" do
      repo = create(:repository, owner: @org)
      AdvisoryDB::Innersource.stub(:repo_authorized?, true) do
        new_advisory = create(:repository_advisory, repository: repo)
        assert_equal new_advisory.repo_advisory_type, "innersource"
      end
    end
  end

  context "#state" do
    test "newly created advisories are open" do
      new_advisory = create(:repository_advisory)
      assert_equal new_advisory.state, "open"
    end
  end

  context "#ghsa_id" do
    test "an Advisory gets a GitHub Security Advisory ID when created" do
      refute_nil @advisory.ghsa_id
      assert(AdvisoryDB.valid_ghsa_id_pattern.match(@advisory.ghsa_id))
    end

    test "the GitHub Security Advisory ID does not change when the Advisory is updated" do
      initial_ghsa_id = @advisory.ghsa_id

      @advisory.update!(title: "Lorem ipsum dolor sit amet")

      assert_equal initial_ghsa_id, @advisory.reload.ghsa_id
    end

    test "the GHSA ID cannot be changed" do
      initial_ghsa_id = @advisory.ghsa_id

      @advisory.update!(ghsa_id: "new-value")

      assert_equal initial_ghsa_id, @advisory.reload.ghsa_id
    end
  end

  context "#owner_id" do
    test "matches owning repository's when created" do
      new_advisory = create(:repository_advisory)
      assert_equal new_advisory.repository.owner_id, new_advisory.owner_id
    end

    test "can not be directly modified" do
      new_advisory = create(:repository_advisory)
      new_advisory.update!(owner_id: 1)
      assert_equal new_advisory.repository.owner_id, new_advisory.reload.owner_id
    end

    test "is updated when owning repository changes owners" do
      new_repo = create(:repository, owner: @org)
      new_advisory = create(:repository_advisory, repository: new_repo)
      new_advisory2 = create(:repository_advisory, repository: new_repo)
      new_owner = create(:organization, admin: @admin)
      original_advisory_owner_id = @advisory.owner_id

      new_advisory.repository.async_transfer_ownership_to(new_owner, actor: @admin)

      assert_equal new_advisory.repository.reload.owner_id, new_advisory.reload.owner_id
      assert_equal new_advisory.repository.owner_id, new_advisory2.reload.owner_id
      assert_equal original_advisory_owner_id, @advisory.reload.owner_id
    end

    test "is cleared when repo is deleted" do
      new_repo = create(:repository, owner: @org, from_example: :simple)
      new_advisory = create(:repository_advisory, repository: new_repo)
      new_advisory2 = create(:repository_advisory, repository: new_repo)

      new_repo.remove(@admin, synchronous: true)
      assert_nil new_advisory.reload.owner_id
      assert_nil new_advisory2.reload.owner_id
    end

    test "is set when repo is restored" do
      # cargo culted from repository_restore_test, makes repository restores work in test env
      Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:repo_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/simple.git")
      GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
        GitHub::GitbackupsTestHelper.restore_from_example(spec)
      end

      new_repo = create(:repository, owner: @org, from_example: :simple)
      new_advisory = create(:repository_advisory, repository: new_repo)
      new_advisory2 = create(:repository_advisory, repository: new_repo)

      new_repo.remove(@admin, synchronous: true)
      assert_nil new_advisory.reload.owner_id
      assert_nil new_advisory2.reload.owner_id

      Repository.restore(new_repo.id, actor: @admin)
      assert_equal new_repo.owner_id, new_advisory.reload.owner_id
      assert_equal new_repo.owner_id, new_advisory2.reload.owner_id
    end
  end

  context "#vulnerability" do
    test "belongs to a Vulnerability with the same GHSA ID" do
      advisory = create(:repository_advisory)
      vulnerability = create(:vulnerability_with_range, ghsa_id: advisory.ghsa_id)

      assert_equal vulnerability, advisory.vulnerability
    end
  end

  context "#set_published" do
    test "an open advisory may be published" do
      assert @advisory.set_published
      @advisory.reload

      assert_predicate @advisory, :published?
      assert_equal @advisory.publisher, @author
      assert_predicate @advisory.published_at, :present?
    end

    test "an open advisory may be published by a specified user" do
      publisher = create(:user)

      assert @advisory.set_published(actor: publisher)
      @advisory.reload

      assert_predicate @advisory, :published?
      assert_equal @advisory.publisher, publisher
      assert_predicate @advisory.published_at, :present?
    end

    test "a closed advisory may not be published" do
      closed_advisory = create(:closed_repository_advisory)

      refute closed_advisory.set_published
      closed_advisory.reload

      refute_predicate closed_advisory.reload, :published?
      refute_predicate closed_advisory.published_at, :present?
    end

    test "a published advisory may not be re-published" do
      published_advisory = create(:published_repository_advisory)
      published_date = published_advisory.published_at

      refute published_advisory.set_published
      published_advisory.reload

      assert_equal published_date, published_advisory.published_at
    end

    test "an advisory may not be published if the repo is empty" do
      empty_repository = create(:empty_repository, owner: @org)
      advisory_for_empty_repository = create(:draft_repository_advisory, repository: empty_repository, author: @org)

      advisory_for_empty_repository.set_published(actor: @publisher)
      refute advisory_for_empty_repository.published?

      advisory_for_empty_repository.repository = @repo
      advisory_for_empty_repository.set_published(actor: @publisher)

      assert advisory_for_empty_repository.published?
    end

    test "an advisory may not be published without a description" do
      @advisory.description = nil
      @advisory.set_published(actor: @publisher)
      refute @advisory.published?

      @advisory.description = "some desc"
      @advisory.set_published(actor: @publisher)

      assert @advisory.published?
    end

    test "an advisory may not be published if the description matches the template" do
      description_template =
      <<~DEFAULT
      ### Impact
      _What kind of vulnerability is it? Who is impacted?_

      ### Patches
      _Has the problem been patched? What versions should users upgrade to?_

      ### Workarounds
      _Is there a way for users to fix or remediate the vulnerability without upgrading?_

      ### References
      _Are there any links users can visit to find out more?_
      DEFAULT

      @advisory.description = description_template
      @advisory.set_published(actor: @publisher)
      refute @advisory.published?
    end

    test "an advisory may not be published without affected_versions" do
      create(:repository_advisory_affected_product,
        repository_advisory: @advisory,
        affected_versions: "< 1.0.0"
      )
      affected_product_without_affected_versions = create(:repository_advisory_affected_product,
        repository_advisory: @advisory,
        affected_versions: nil
      )
      create(:repository_advisory_affected_product,
        repository_advisory: @advisory,
        affected_versions: " < 2.0.0"
      )

      @advisory.set_published(actor: @publisher)
      refute @advisory.published?

      affected_product_without_affected_versions.update!(affected_versions: "< 1.2.3")
      @advisory.reload.set_published(actor: @publisher)

      assert @advisory.published?
    end

    test "an advisory may not be published without severity even though it can be opened without severity" do
      @advisory.severity = nil
      @advisory.set_published(actor: @publisher)
      refute @advisory.form_filled_out?
      refute @advisory.published?

      @advisory.severity = "low"
      @advisory.set_published(actor: @publisher)

      assert @advisory.form_filled_out?
      assert @advisory.published?
    end

  end

  context "#set_closed" do
    test "an open advisory may be closed" do
      assert @advisory.set_closed
      @advisory.reload

      assert_predicate @advisory, :closed?
      assert_predicate @advisory.closed_at, :present?
    end

    test "a published advisory may not be closed" do
      published_advisory = create(:published_repository_advisory)

      refute published_advisory.set_closed
      published_advisory.reload

      refute_predicate published_advisory, :closed?
      refute_predicate published_advisory.closed_at, :present?
    end

    test "a closed advisory may not be set to closed" do
      closed_advisory = create(:closed_repository_advisory)
      closed_date = closed_advisory.closed_at

      refute closed_advisory.set_closed
      closed_advisory.reload

      assert_equal closed_date, closed_advisory.closed_at
    end
  end

  context "#set_open" do
    test "a closed advisory may be re-opened" do
      closed_advisory = create(:closed_repository_advisory)

      assert closed_advisory.set_open
      closed_advisory.reload

      assert_predicate closed_advisory, :open?
      assert_nil closed_advisory.closed_at
    end

    test "an open advisory may not be set to open" do
      refute @advisory.set_open
    end

    test "a published advisory may not be set back to open" do
      published_advisory = create(:published_repository_advisory)

      refute published_advisory.set_open
      published_advisory.reload

      refute_predicate published_advisory, :open?
      refute_nil published_advisory.publisher
      refute_nil published_advisory.published_at
    end
  end

  context "#description_or_template" do
    test "on blank description, template gets served" do
      new_adv = RepositoryAdvisory.new

      assert new_adv.description.nil?
      assert_match(/vulnerability/, new_adv.description_or_template)

      new_adv.description = "Whatever"
      assert_equal "Whatever", new_adv.description_or_template
    end
  end

  context "events" do
    test "#add_state_event handles input properly" do
      new_adv = create(:repository_advisory)

      assert_equal 0, new_adv.events.count
      new_adv.add_state_event(@admin, "closed")

      assert_equal 1, new_adv.events.where(event: "closed").count
      new_adv.add_state_event(@admin, "bad-event-name")
      assert_equal 1, new_adv.events.count
    end

    test "#add_rename_event handles input properly" do
      new_adv = create(:repository_advisory)

      assert_equal 0, new_adv.events.count
      new_adv.add_rename_event(@admin, "old title", "new title")

      assert_equal 1, new_adv.events.where(event: "renamed").count
    end

    test "#add_collaborator adds adds collaborator event" do
      assert_changes -> { @advisory.events.count }, 1 do
        collaborator = create(:user)
        @advisory.add_collaborator(collaborator)
      end

      assert_equal "collaborator_added", @advisory.events.last.event
    end

    test "#add_collaborator adds collaborator event for teams" do
      assert_changes -> { @advisory.events.count }, 1 do
        collaborator = create(:team, organization: @org)
        @advisory.add_collaborator(collaborator)
      end
    end

    test "#remove_collaborator adds collaborator event for users" do
      assert_changes -> { @advisory.events.count }, 1 do
        @advisory.remove_collaborator(@collab)
      end

      assert_equal "collaborator_removed", @advisory.events.last.event
    end

    test "#remove_collaborator adds collaborator event for teams" do
      assert_changes -> { @advisory.events.count }, 1 do
        @advisory.remove_collaborator(@team)
      end
    end

    test "#remove_collaborator does not add collaborator event if user is not a collaborator" do
      assert_no_changes -> { @advisory.events.count } do
        @advisory.remove_collaborator(@rando)
      end
    end

    test "#add_workspace_created_event adds workspace_created event", skip_enterprise: true do
      setup_staff_user
      assert_changes -> { @advisory.events.count }, 1 do
        # Does not create the repo, just logs an event
        @advisory.add_workspace_created_event(@workspace_repo)
      end

      assert_equal "workspace_created", @advisory.events.last.event
    end

    test "#add_workspace_deleted_event adds adds workspace_deleted event", skip_enterprise: true do
      setup_staff_user
      assert_changes -> { @advisory.events.count }, 1 do
        # Does not destroy the repo, just logs an event
        @advisory.add_workspace_deleted_event(@workspace_repo)
      end

      assert_equal "workspace_deleted", @advisory.events.last.event
    end
  end

  context "#pull_requests" do
    test "includes open and merged pull requests" do
      @workspace_pull1.update(merged_at: 1.minute.ago)
      assert_predicate @workspace_pull1, :merged?
      assert_predicate @workspace_pull2, :open?

      assert_same_elements [@workspace_pull1, @workspace_pull2], @advisory.reload.pull_requests.to_a
    end

    test "excludes closed pull requests" do
      @workspace_pull1.close(@admin)

      assert_equal [@workspace_pull2], @advisory.reload.pull_requests.to_a
    end
  end

  context "#open_pull_requests" do
    test "only returns open pull requests" do
      assert_same_elements [@workspace_pull1, @workspace_pull2], @advisory.open_pull_requests.to_a

      assert @workspace_pull1.close(@admin)

      assert_same_elements [@workspace_pull2], deep_reload(@advisory).open_pull_requests.to_a

      assert @workspace_pull2.close(@admin)

      assert_empty deep_reload(@advisory).open_pull_requests.to_a
    end
  end

  context "#recently_touched_branches" do
    test "returns branches that have been recently pushed to in the workspace" do
      Timecop.freeze(pushed_at = Time.now) do
        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          @workspace_repo.heads.find("outsider-topic").append_commit({ message: "Bumping the branch", committer: @admin }, @admin) do |files|
            files.add("new-file", "foobar")
          end
        end
      end

      branches = @advisory.recently_touched_branches
      assert_equal 1, branches.count
      pushed_branch = branches.pop

      assert_equal "outsider-topic", pushed_branch[:name]
      assert_equal pushed_at.to_formatted_s(:db), pushed_branch[:pushed_at].to_formatted_s(:db)
    end

    test "only returns pushes within the recency threshold" do
      threshold = 24.hours.ago

      Timecop.freeze(threshold - 5.minutes) do
        @workspace_repo.heads.find("outsider-topic").append_commit({ message: "Bumping the branch", committer: @admin }, @admin) do |files|
          files.add("new-file", "foobar")
        end
      end

      Timecop.freeze(threshold + 5.minutes) do
        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          @workspace_repo.heads.find("ahead").append_commit({ message: "Bumping the branch", committer: @admin }, @admin) do |files|
            files.add("new-file", "foobar")
          end
        end
      end

      branches = @advisory.recently_touched_branches
      assert_equal 1, branches.count
      assert_equal "ahead", branches.first[:name]
    end

    test "doesn't include pushed branches that were deleted" do
      Timecop.freeze(5.minutes.ago) do
        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          ref_target = @workspace_repo.heads.find("master").target_oid
          ref = Git::Ref.new(@workspace_repo, "refs/heads/temp-branch")
          ref.create(ref_target, @admin)

          ref.append_commit({ message: "Bumping the branch", committer: @admin }, @admin) do |files|
            files.add("new-file", "foobar")
          end
        end
      end

      branches = @advisory.recently_touched_branches
      assert_equal 1, branches.count
      assert_equal "temp-branch", branches.first[:name]

      @advisory = deep_reload(@advisory)

      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
        ref = @workspace_repo.heads.find("temp-branch")
        ref.delete(@admin)
      end

      assert_empty @advisory.recently_touched_branches
    end

    test "doesn't return recently pushed branches that already have pull requests" do
      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
        @workspace_repo.heads.find("outsider-topic").append_commit({ message: "Bumping the branch", committer: @admin }, @admin) do |files|
          files.add("new-file", "foobar")
        end

        @workspace_repo.heads.find(@workspace_pull2.head_ref).append_commit({ message: "Bumping the branch", committer: @admin }, @admin) do |files|
          files.add("new-file", "foobar")
        end
      end

      branches = @advisory.recently_touched_branches
      assert_equal 1, branches.count
      assert_equal "outsider-topic", branches.first[:name]
    end
  end

  context "#cleanup_workspace" do
    test "it enqueues a repository delete job" do
      GitHub.flipper[:advisory_db_unrestorable_repositories].enable(@repo)
      old_workspace_repository = @advisory.workspace_repository
      @advisory.cleanup_workspace(@publisher)

      # Check the workspace repo has been logically deleted and unlinked
      old_workspace_repository.reload
      assert old_workspace_repository.deleted?
      assert_nil @advisory.workspace_repository
    end
  end

  context "mention suggestions" do
    test "suggests repository admin and advisory collaborators" do
      mentionables = @advisory.mentionable_users_for(@admin)
      assert_equal [@admin, @collab].sort, mentionables.sort
    end
  end

  context "#timeline_for" do
    test "returns viewer-specific comments and events when published" do
      # For variable scoping:
      before_publication = T.let(nil, T.nilable(T::Array[T.any(RepositoryAdvisoryComment, RepositoryAdvisoryEvent)]))
      after_publication = T.let(nil, T.nilable(T::Array[T.any(RepositoryAdvisoryComment, RepositoryAdvisoryEvent)]))

      # This advisory will be published with events on either side of publication time
      Timecop.freeze(@advisory.created_at + 10.minutes) do
        # account for existing collaborator_added events
        assert_equal 3, @advisory.events.count
        before_publication = [
          @advisory.events.first,
          @advisory.events.second,
          @advisory.events.last,
          @advisory.comments.first,
          @advisory.comments.second,
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 5.minutes.ago),
          create(:repository_advisory_event, :closed,    repository_advisory: @advisory, actor: @admin, created_at: 4.minutes.ago),
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 3.minutes.ago),
          create(:repository_advisory_event, :reopened,  repository_advisory: @advisory, actor: @admin, created_at: 2.minutes.ago),
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 1.minute.ago),
        ].sort_by(&:created_at)

        @advisory.set_published

        after_publication = [
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 1.minute.from_now),
          create(:repository_advisory_event, :closed,    repository_advisory: @advisory, actor: @admin, created_at: 2.minutes.from_now),
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 3.minutes.from_now),
          create(:repository_advisory_event, :reopened,  repository_advisory: @advisory, actor: @admin, created_at: 4.minutes.from_now),
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 5.minutes.from_now),
        ]
      end

      admin_timeline = @advisory.timeline_for(@admin)
      sec_man_timeline = @advisory.timeline_for(@security_manager)
      collab_timeline = @advisory.timeline_for(@collab)
      rando_timeline  = @advisory.timeline_for(@rando)

      assert_equal T.must(before_publication) + [@advisory.events.published.first] + T.must(after_publication), admin_timeline
      assert_equal T.must(before_publication) + [@advisory.events.published.first] + T.must(after_publication), sec_man_timeline
      assert_equal T.must(before_publication) + [@advisory.events.published.first] + T.must(after_publication), collab_timeline
      assert_equal after_publication, rando_timeline
    end

    test "returns no comments or events when unpublished" do
      # For variable scoping:
      before_publication = T.let(nil, T.nilable(T::Array[T.any(RepositoryAdvisoryComment, RepositoryAdvisoryEvent)]))

      Timecop.freeze(@advisory.created_at + 10.minutes) do
        # account for existing collaborator_added events
        assert_equal 3, @advisory.events.count
        before_publication = [
          @advisory.events.first,
          @advisory.events.second,
          @advisory.events.last,
          @advisory.comments.first,
          @advisory.comments.second,
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 5.minutes.ago),
          create(:repository_advisory_event, :closed,    repository_advisory: @advisory, actor: @admin, created_at: 4.minutes.ago),
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 3.minutes.ago),
          create(:repository_advisory_event, :reopened,  repository_advisory: @advisory, actor: @admin, created_at: 2.minutes.ago),
          create(:repository_advisory_comment,           repository_advisory: @advisory,  user: @admin, created_at: 1.minute.ago),
        ].sort_by(&:created_at)
      end

      admin_timeline = @advisory.timeline_for(@admin)
      sec_man_timeline = @advisory.timeline_for(@security_manager)
      collab_timeline = @advisory.timeline_for(@collab)
      rando_timeline  = @advisory.timeline_for(@rando)

      assert_equal before_publication, admin_timeline
      assert_equal before_publication, sec_man_timeline
      assert_equal before_publication, collab_timeline
      assert_equal [], rando_timeline
    end
  end

  context "#create_comment" do
    test "returns an unsaved comment if the repository advisory is already published" do
      @advisory.set_published
      comment = @advisory.create_comment(@collab, "A comment")

      assert_kind_of RepositoryAdvisoryComment, comment
      refute comment.persisted?
    end

    test "returns a valid, saved comment if the repository advisory is still a draft" do
      @advisory.set_open

      collab_comment = @advisory.create_comment(@collab, "A comment")

      assert_kind_of RepositoryAdvisoryComment, collab_comment
      assert collab_comment.valid?
      assert collab_comment.persisted?
    end

    test "returns a saved, valid comment if the repository advisory is closed" do
      @advisory.set_closed

      collab_comment = @advisory.create_comment(@collab, "A comment")

      assert_kind_of RepositoryAdvisoryComment, collab_comment
      assert collab_comment.valid?
      assert collab_comment.persisted?
    end
  end

  context "#html_url" do
    test "returns a link to advisory on a repository" do
      repo = create(:repository)
      advisory = create(:published_repository_advisory, repository: repo)

      url = advisory.html_url

      refute_nil url
      uri = Addressable::URI.parse(url)
      assert_equal GitHub.scheme, uri.scheme
      assert_equal GitHub.host_name, uri.host
      assert_equal "/#{repo.nwo}/security/advisories/#{advisory.ghsa_id}", uri.path
    end
  end

  context "pending CVE requests" do
    test "marks a CVE request as pending" do
      refute @advisory.cve_request_pending?

      @advisory.cve_request_pending!

      assert @advisory.cve_request_pending?

      @advisory.reset_cve_request

      refute @advisory.cve_request_pending?
    end

    test "expires after 72 hours" do
      refute @advisory.cve_request_pending?
      Timecop.travel(Time.zone.local(2022, 6, 1, 13, 0, 0)) do
        @advisory.cve_request_pending!

        assert @advisory.cve_request_pending?

        # 1 hour before expiration
        Timecop.travel(71.hours.from_now) do
          assert @advisory.cve_request_pending?
        end

        # 1 hour after expiration
        Timecop.travel(73.hours.from_now) do
          refute @advisory.cve_request_pending?
        end
      end
    end

    test "bumps expiration with every request" do
      refute @advisory.cve_request_pending?

      @advisory.cve_request_pending!

      assert @advisory.cve_request_pending?

      # Request another CVE a day later
      Timecop.travel(24.hours.from_now) do
        @advisory.cve_request_pending!
      end

      # 1 hour after original expiration, 23 hours before new expiration
      Timecop.travel(73.hours.from_now) do
        assert @advisory.cve_request_pending?
      end

      # 1 hour after new expiration
      Timecop.travel(97.hours.from_now) do
        refute @advisory.cve_request_pending?
      end
    end
  end

  context "instrumentation" do
    test "instruments an open event" do
      events = subscribe("repository_advisory.open")
      advisory = create(:repository_advisory)

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(advisory), event.payload
    end

    test "instruments a publish event" do
      events = subscribe("repository_advisory.publish")
      @advisory.set_published

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(@advisory, org: @org), event.payload
    end

    test "instruments a reopen event" do
      events = subscribe("repository_advisory.reopen")

      closed_advisory = create(:closed_repository_advisory)
      closed_advisory.set_open

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(closed_advisory), event.payload
    end

    test "instruments a close event" do
      events = subscribe("repository_advisory.close")

      @advisory.set_closed

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(@advisory, org: @org), event.payload
    end

    test "instruments an update event" do
      events = subscribe("repository_advisory.update")

      old_title = @advisory.title
      @advisory.handle_update(@advisory.user, title: "Changed it!")

      updated_payload = expected_payload(@advisory, org: @org).merge!(
        title_was: old_title,
        title: "Changed it!",
      )

      assert event = events.pop, "an event was expected"
      assert_same_hash updated_payload, event.payload
    end

    test "instruments an update event when old value is nil" do
      events = subscribe("repository_advisory.update")

      advisory = create(:repository_advisory, description: nil)
      advisory.update!(description: "It's a new description")

      updated_payload = expected_payload(advisory).merge!(
        description_was: nil,
        description: "It's a new description",
      )

      assert event = events.pop, "an event was expected"
      assert_same_hash updated_payload, event.payload
    end

    test "instruments an create event for CWEs", skip_enterprise: true do
      events = subscribe("repository_advisory.update")

      cwe = create(:cwe, cwe_id: "CWE-79", name: "Cross site1")

      advisory = create(:repository_advisory)
      advisory.update!(cwes: [cwe])

      updated_payload = expected_payload(advisory).merge!(
        "added_cwe": cwe.cwe_id
      )

      assert event = events.pop, "an event was expected"
      assert_same_hash updated_payload, event.payload
    end

    test "instruments a destroy event for CWEs", skip_enterprise: true do
      events = subscribe("repository_advisory.update")

      cwe = create(:cwe, cwe_id: "CWE-79", name: "Cross site1")

      advisory = create(:repository_advisory, cwes: [cwe])
      advisory.update!(cwes: [])

      updated_payload = expected_payload(advisory).merge!(
        "removed_cwe": cwe.cwe_id
      )

      assert event = events.pop, "an event was expected"
      assert_same_hash updated_payload, event.payload
    end

    test "instruments an update event for CVSS v3", skip_enterprise: true do
      events = subscribe("repository_advisory.update")

      advisory = create(:repository_advisory)
      advisory.update!(cvss_v3: "CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H")

      updated_payload = expected_payload(advisory).merge!(
        cvss_v3_was: nil,
        cvss_v3: "CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H",
      )

      assert event = events.pop, "an event was expected"
      assert_same_hash updated_payload, event.payload
    end

    test "instruments an update event for CVSS v4", skip_enterprise: true do
      events = subscribe("repository_advisory.update")

      advisory = create(:repository_advisory)
      advisory.update!(cvss_v4: "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:P/VC:L/VI:H/VA:H/SC:H/SI:L/SA:L")

      updated_payload = expected_payload(advisory).merge!(
        cvss_v4_was: nil,
        cvss_v4: "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:P/VC:L/VI:H/VA:H/SC:H/SI:L/SA:L",
      )

      assert event = events.pop, "an event was expected"
      assert_same_hash updated_payload, event.payload
    end

    test "instruments a cve_request event", skip_enterprise: true do
      events = subscribe("repository_advisory.cve_request")

      @advisory.add_cve_requested_event(@admin)

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(@advisory, org: @org), event.payload
    end

    test "instruments a cve_assignment event", skip_enterprise: true do
      events = subscribe("repository_advisory.cve_assignment")

      @advisory.add_cve_assigned_event

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(@advisory, org: @org), event.payload
    end

    test "instruments a declined_cve_assignment event", skip_enterprise: true do
      events = subscribe("repository_advisory.declined_cve_assignment")

      @advisory.add_cve_not_assigned_event

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(@advisory, org: @org), event.payload
    end

    test "instruments a github_broadcast event", skip_enterprise: true do
      events = subscribe("repository_advisory.github_broadcast")

      vulnerability = create :vulnerability_with_range, :with_repository_advisory, status: :unreviewed
      advisory = vulnerability.repository_advisory

      vulnerability.update(status: :published, published_at: Time.now)

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(advisory), event.payload
    end

    test "instruments a github_withdraw event", skip_enterprise: true do
      events = subscribe("repository_advisory.github_withdraw")

      vulnerability = create :published_vulnerability, :with_repository_advisory
      advisory = vulnerability.repository_advisory

      vulnerability.update(status: :withdrawn, withdrawn_at: Time.now)

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload(advisory), event.payload
    end
  end

  context "#handle_update" do
    test "it emits a rename event, and adds user content edits" do
      old_title = @advisory.title
      old_desc = @advisory.description
      old_severity = @advisory.severity

      assert_equal 0, @advisory.user_content_edits.count
      assert_equal 0, @advisory.events.where(event: "renamed").count
      assert @advisory.handle_update(@advisory.user, { title: "new title!!!!!!",
                                                       description: "new description!",
                                                       severity: "critical" })

      @advisory.reload
      refute_equal old_title, @advisory.title
      refute_equal old_desc, @advisory.description
      refute_equal old_severity, @advisory.severity

      # two content edits because the initial content has to be seeded
      assert_equal 2, @advisory.user_content_edits.count
      assert_equal 1, @advisory.events.where(event: "renamed").count

      assert @advisory.handle_update(@advisory.user, { description: "yet a different desc!!!" })

      assert_equal 3, @advisory.user_content_edits.count
      # title wasn't changed, so no new renamed event
      assert_equal 1, @advisory.events.where(event: "renamed").count
    end

    test "it rolls back txn in event of invalid input" do
      old_title = @advisory.title
      old_desc = @advisory.description
      old_cve_id = @advisory.cve_id

      refute @advisory.handle_update(@advisory.user, { title: "new title!!!!!",
                                                      description: "new desc!!!!!!",
                                                      cve_id: "invalid input" })

      @advisory.reload

      assert_equal old_title, @advisory.title
      assert_equal old_desc, @advisory.description
      assert_equal old_cve_id, @advisory.cve_id
      assert_equal 0, @advisory.user_content_edits.count
      assert_equal 0, @advisory.events.where(event: "renamed").count
    end

    test "it rolls back txn in event of an error" do
      @advisory.stubs(:add_user_content_edit!).raises(ActiveRecord::RecordInvalid.new)

      old_title = @advisory.title
      old_desc = @advisory.description

      begin
        refute @advisory.handle_update(@advisory.user, { title: "new title!!!!!",
                                                        description: "new desc!!!!!!" })
      rescue ActiveRecord::RecordInvalid
      end

      @advisory.reload
      assert_equal old_title, @advisory.title
      assert_equal old_desc, @advisory.description
      assert_equal 0, @advisory.events.where(event: "renamed").count
    end
  end

  context "rate limits" do
    test "are present for the creation of a repository advisory when rate limiting is enabled" do
      enable_content_creation_rate_limiting
      author = create(:user)
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              repository_advisory = build(:repository_advisory, author: author)
              assert repository_advisory.save
            end

            another_repository_advisory = build(:repository_advisory, author: author)
            refute another_repository_advisory.save
          end
        end
      end
    end

    test "are not present for the creation of a repository advisory when rate limiting is disabled" do
      disable_content_creation_rate_limiting
      author = create(:user)
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              repository_advisory = build(:repository_advisory, author: author)
              assert repository_advisory.save
            end

            another_repository_advisory = build(:repository_advisory, author: author)
            assert another_repository_advisory.save
          end
        end
      end
    end
  end

  context "#body_version_attributes" do
    test "returns a string containing applicable attributes" do
      # expected format: "[:title, :body, :severity, :description, :cvss_v3, :cvss_v4 :cve_id]"
      expected = "[\"💎 Path Traversal on Default Installed Rails Application\", nil, \"moderate\", \"**Urgent**: Vulnerability has been _disclosed_ 😱\\n\\n[Read more here](https://example.com/oh-noes)\\n\", nil, nil, \"CVE-1900-0001\"]"
      assert_equal expected, @advisory.send(:body_version_attributes)
    end
  end

  context ".multiple_target_for_conditional_access" do
    test "computes TFCA for multiple repository advisories" do
      second_advisory = create(:repository_advisory, repository: @repo)
      advisories = [@advisory, second_advisory]
      result = RepositoryAdvisory.multiple_target_for_conditional_access(advisories)
      expected = advisories.each_with_object({}) { |v, h| h[v] = v.repository.owner }
      assert_equal expected, result
    end

    test "raises if a different type of object is provided" do
      assert_raises ArgumentError do
        RepositoryAdvisory.multiple_target_for_conditional_access(Organization.all)
      end
    end
  end

  context "#target_for_conditional_access" do
    test "returns the repo owner when available" do
      assert_equal @org, @advisory.target_for_conditional_access
    end
  end

  context "#async_target_for_conditional_access" do
    test "returns the repo owner when available" do
      assert_equal @org, @advisory.async_target_for_conditional_access.sync
    end
  end

  context "#og_image_url" do
    test "it returns enhanced opengraph image url with correct cache key" do
      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          @advisory.updated_at,
          @advisory.repository.owner_id,
          @advisory.repository.private?,
          @advisory.affected_products.to_json(only: [
            :affected_functions,
            :affected_versions,
            :ecosystem,
            :id,
            :package,
            :patches,
            :repository_advisory_id
          ]),
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "http://localhost:7071/#{cache_key}#{@advisory.permalink(include_host: false)}"

      assert_equal image_url, @advisory.og_image_url
    end

    test "changing package name of an affected product also changes the cache key" do
      assert_changes "@advisory.og_image_url" do
        @advisory.affected_products.last.update!(package: "new name")
      end
    end

    test "changing ecosystem of an affected product also changes the cache key" do
      assert_changes "@advisory.og_image_url" do
        @advisory.affected_products.last.update!(ecosystem: "some_other_ecosystem")
      end
    end
  end

  context "#affected_products" do
    test "returns the affected product entries" do
      assert_equal 1, @advisory.affected_products.length
      @advisory.affected_products.create!
      @advisory.affected_products.create!

      assert_equal 3, @advisory.affected_products.length
    end

    test "are deleted via destroy_dependents_in_background when the repository advisory is deleted" do
      @advisory.affected_products.create!
      @advisory.affected_products.create!
      assert_equal 3, @advisory.affected_products.length

      assert_difference "RepositoryAdvisoryAffectedProduct.count", -3 do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          @advisory.destroy!
        end
      end
    end
  end

  context "#credits" do
    test "are destroyed via DestroyOrNullifyAdvisoryCreditsJob when the repository advisory is destroyed" do
      assert_equal 1, @advisory.credits.length

      assert_difference "AdvisoryCredit.count", -1 do
        perform_enqueued_jobs(only: [DestroyOrNullifyAdvisoryCreditsJob]) do
          @advisory.destroy!
        end
      end
    end
  end

  [:title, :description, :body].each do |field|
    test "supports emoji for #{field}" do
      advisory = create(:repository_advisory, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(advisory, field)
    end
  end

  test "supports UTF-8 using StringFromBinary" do
    cve_id = "CVE-1900-0001"
    cvss_v3 = "CVSS:3.0/AV:L/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N/E:P/RL:T/RC:U/CR:L/IR:H/AR:H/MAV:L/MAC:L/MPR:L/MUI:N/MS:U/MC:L/MI:N/MA:H"
    cvss_v4 = "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:P/VC:L/VI:H/VA:H/SC:H/SI:L/SA:L"

    advisory = create(:repository_advisory, cve_id: cve_id, cvss_v3: cvss_v3)
    advisory.reload

    advisory_cvss_v4 = create(:repository_advisory, cve_id: cve_id, cvss_v4: cvss_v4)
    advisory_cvss_v4.reload

    [:cve_id, :cvss_v3].each do |field|
      assert_equal StringFromBinary.new, advisory.type_for_attribute(field)
      assert_equal Encoding::UTF_8, advisory.send(field).encoding
    end

    assert_equal StringFromBinary.new, advisory_cvss_v4.type_for_attribute(:cvss_v4)
    assert_equal Encoding::UTF_8, advisory_cvss_v4.send(:cvss_v4).encoding
  end

  [:value_was, :value_is].each do |field|
    test "supports emoji for #{field}" do
      repository_advisory_event = create(:repository_advisory_event, :renamed, :repository_advisory => @advisory, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(repository_advisory_event, field)
    end
  end

  context "scoped vulnerabilities" do
    test "can belong to scoped and unscoped vulnerabilities as repository advisory" do
      advisory = create(:repository_advisory, repository: create(:private_repository))
      vuln = create(:vulnerability, :with_repository_advisory, repository_advisory: advisory)
      scoped_vuln = create(:innersource_vulnerability, id: vuln.id, ghsa_id: advisory.ghsa_id, advisory_repository_id: advisory.repository_id, security_advisory_id: advisory.id)

      assert_equal vuln.repository_advisory, scoped_vuln.repository_advisory
      assert_nil advisory.scoped_vulnerability
      advisory.reload
      assert_equal scoped_vuln, advisory.with_scope(:innersource).scoped_vulnerability
    end
  end

  def deep_reload(advisory)
    RepositoryAdvisory.find(advisory.id)
  end

  def expected_payload(advisory, org: nil)
    payload = {
      repository_advisory: advisory.ghsa_id,
      repository_advisory_id: advisory.id,
      repo: advisory.repository.nwo,
      repo_id: advisory.repository.id,
      public_repo: advisory.repository.public?,
    }

    if org
      payload.merge!(
        org: org.login,
        org_id: org.id,
      )
    end

    payload
  end
end
