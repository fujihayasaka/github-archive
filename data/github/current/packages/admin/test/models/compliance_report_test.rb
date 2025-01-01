# typed: true
# frozen_string_literal: true

require "test_helper"

class ComplianceReportTest < GitHub::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  fixtures do
    @report = create :compliance_report, display_order: 0
  end

  setup do
    @azure_client = mock("azure client")
    GHECAdmin::AzureStorage.any_instance.stubs(:azure_blob_client).returns(@azure_client)
  end

  context "validations" do
    test "require that slug is present" do
      report = build :compliance_report, slug: ""
      refute_predicate report, :valid?
      assert_includes report.errors[:slug], "can't be blank"
    end

    test "require that slug is unique" do
      create :compliance_report, slug: "soc1"
      report = build :compliance_report, slug: "soc1"
      refute_predicate report, :valid?
      assert_includes report.errors[:slug], "has already been taken"
    end

    test "require that slug has correct length" do
      report = build :compliance_report, slug: "e" * 120
      refute_predicate report, :valid?
      assert_includes report.errors[:slug], "is too long (maximum is 100 characters)"
    end

    test "require that slug has valid format" do
      report = build :compliance_report, slug: "not a valid slug"
      refute_predicate report, :valid?
      assert_includes \
        report.errors[:slug],
        "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
    end

    test "require that report_type is present" do
      report = build :compliance_report, report_type: ""
      refute_predicate report, :valid?
      assert_includes report.errors[:report_type], "can't be blank"
    end

    test "require that report_type is valid" do
      report = build :compliance_report, report_type: "invalid"
      refute_predicate report, :valid?
      assert_includes report.errors[:report_type], "is not included in the list"
    end

    test "require that filename is present when report_type is download" do
      report = build :compliance_report, report_type: "download", filename: ""
      refute_predicate report, :valid?
      assert_includes report.errors[:filename], "can't be blank"
    end

    test "require that filename has correct length" do
      report = build :compliance_report, report_type: "download", filename: %Q[#{"e" * 300}.pdf]
      refute_predicate report, :valid?
      assert_includes report.errors[:filename], "is too long (maximum is 250 characters)"
    end

    test "require that filename has valid format" do
      report = build :compliance_report, report_type: "download", filename: "unacceptable file name. what"
      refute_predicate report, :valid?
      assert_includes \
        report.errors[:filename],
        "may only contain alphanumeric characters, hyphens, underscores, and periods"
    end

    test "require that url is present when report_type is link" do
      report = build :compliance_report, report_type: "link", url: ""
      refute_predicate report, :valid?
      assert_includes report.errors[:url], "can't be blank"
    end

    test "require that url has correct length" do
      report = build :compliance_report, report_type: "link", url: %Q[https://#{"e" * 300}.lol]
      refute_predicate report, :valid?
      assert_includes report.errors[:url], "is too long (maximum is 250 characters)"
    end

    test "require that url has valid format" do
      report = build :compliance_report, report_type: "link", url: "not a URL"
      refute_predicate report, :valid?
      assert_includes report.errors[:url], "is not a valid http(s) URL"
    end

    test "require that title is present" do
      report = build :compliance_report, title: ""
      refute_predicate report, :valid?
      assert_includes report.errors[:title], "can't be blank"
    end

    test "require that title has correct length" do
      report = build :compliance_report, report_type: "link", title: "e" * 300
      refute_predicate report, :valid?
      assert_includes report.errors[:title], "is too long (maximum is 250 characters)"
    end

    test "require that description is present" do
      report = build :compliance_report, description: ""
      refute_predicate report, :valid?
      assert_includes report.errors[:description], "can't be blank"
    end

    test "require that display_order is an integer" do
      report = build :compliance_report, display_order: "whatever"
      refute_predicate report, :valid?
      assert_includes report.errors[:display_order], "is not a number"
    end
  end

  context "creation" do
    test "stores provided blob for download report" do
      filename = "rails.svg"
      blob = file_fixture_upload(filename)
      @azure_client.stubs(:create_block_blob)

      report = ComplianceReport.create! \
        slug: "some-new-download-8789238479283",
        title: "New download",
        report_type: "download",
        description: "Important description",
        filename: filename,
        blob: blob

      report.reload
      assert_predicate report, :download?
    end
  end

  context "destruction" do
    test "removes associated blob for download report" do
      filename = "rails.svg"
      blob = file_fixture_upload(filename)
      @azure_client.stubs(:create_block_blob)

      report = ComplianceReport.create! \
        slug: "some-new-download-8789238479283",
        title: "New download",
        report_type: "download",
        description: "Important description",
        filename: filename,
        blob: blob

      report.reload
      assert_predicate report, :download?

      @azure_client.stubs(:get_blob_properties)
      @azure_client.stubs(:delete_blob)
      report.destroy!

      assert_nil ComplianceReport.find_by id: report.id
    end
  end

  context "published scope" do
    test "returns only published reports" do
      unpublished = create :compliance_report, published: false

      assert_equal [@report], ComplianceReport.published
    end
  end

  context "downloads scope" do
    test "returns only reports with report_type download" do
      link = create :compliance_report, report_type: "link", url: "https://example.com"

      assert_equal [@report], ComplianceReport.downloads
    end
  end

  context "top_level_reports scope" do
    test "returns top level reports ordered by display_order" do
      group = create :compliance_report, report_type: "group", display_order: 3
      child_one = create :compliance_report, report_type: "download", parent_id: group.id
      parent_one = create :compliance_report, report_type: "download", display_order: 1
      parent_two = create :compliance_report, report_type: "link", url: "https://example.com", display_order: 2

      assert_equal \
        [@report, parent_one, parent_two, group],
        ComplianceReport.top_level_reports
    end
  end

  context "for_ghec_account scope" do
    test "returns the right reports for GHEC accounts" do
      create :compliance_report, availability: :non_ghec_accounts_only
      ghec_only_report = create :compliance_report, availability: :ghec_accounts_only
      all_accounts_report = create :compliance_report, availability: :all_accounts
      assert_same_elements \
        [@report, ghec_only_report, all_accounts_report],
        ComplianceReport.for_ghec_account
    end
  end

  context "for_non_ghec_account scope" do
    test "returns the right reports for non-GHEC accounts" do
      create :compliance_report, availability: :ghec_accounts_only
      non_ghec_only_report = create :compliance_report, availability: :non_ghec_accounts_only
      all_accounts_report = create :compliance_report, availability: :all_accounts
      assert_same_elements \
        [non_ghec_only_report, all_accounts_report],
        ComplianceReport.for_non_ghec_account
    end
  end

  context "#availability" do
    test "defaults to ghec_accounts_only" do
      assert_predicate @report, :ghec_accounts_only?
      refute_predicate @report, :non_ghec_accounts_only?
      refute_predicate @report, :all_accounts?
    end

    test "can be non_ghec_accounts_only" do
      @report.update! availability: :non_ghec_accounts_only
      assert_predicate @report, :non_ghec_accounts_only?
      refute_predicate @report, :ghec_accounts_only?
      refute_predicate @report, :all_accounts?
    end

    test "can be all_accounts" do
      @report.update! availability: :all_accounts
      assert_predicate @report, :all_accounts?
      refute_predicate @report, :non_ghec_accounts_only?
      refute_predicate @report, :ghec_accounts_only?
    end
  end

  context "::availability_for_humans" do
    test "returns human readable version of availability when ghec_accounts_only" do
      assert_predicate @report, :ghec_accounts_only?
      assert_equal "GHEC accounts only", ComplianceReport.availability_for_humans(@report.availability)
    end

    test "returns human readable version of availability when non_ghec_accounts_only" do
      @report.update! availability: :non_ghec_accounts_only
      assert_predicate @report, :non_ghec_accounts_only?
      assert_equal "Non-GHEC accounts only", ComplianceReport.availability_for_humans(@report.availability)
    end

    test "returns human readable version of availability when all_accounts" do
      @report.update! availability: :all_accounts
      assert_predicate @report, :all_accounts?
      assert_equal "All accounts", ComplianceReport.availability_for_humans(@report.availability)
    end
  end

  context "#available_to?" do
    test "always returns false for Users" do
      user = create :user
      refute @report.available_to?(user)
    end

    context "when provided a Business" do
      test "returns true when availability is all_accounts" do
        business = create :business
        @report.all_accounts!

        assert_predicate @report, :all_accounts?
        assert @report.available_to?(business)
      end

      test "returns true when availability is ghec_accounts_only" do
        business = create :business
        @report.ghec_accounts_only!

        assert_predicate @report, :ghec_accounts_only?
        assert @report.available_to?(business)
      end

      test "returns false when availability is non_ghec_accounts_only" do
        business = create :business
        @report.non_ghec_accounts_only!

        assert_predicate @report, :non_ghec_accounts_only?
        refute @report.available_to?(business)
      end
    end

    context "when provided a business_plus Organization" do
      test "returns true when availability is all_accounts" do
        org = create :business_plus_organization
        @report.all_accounts!

        assert_predicate org, :business_plus?
        assert_predicate @report, :all_accounts?
        assert @report.available_to?(org)
      end

      test "returns true when availability is ghec_accounts_only" do
        org = create :business_plus_organization
        @report.ghec_accounts_only!

        assert_predicate org, :business_plus?
        assert_predicate @report, :ghec_accounts_only?
        assert @report.available_to?(org)
      end

      test "returns false when availability is non_ghec_accounts_only" do
        org = create :business_plus_organization
        @report.non_ghec_accounts_only!

        assert_predicate org, :business_plus?
        assert_predicate @report, :non_ghec_accounts_only?
        refute @report.available_to?(org)
      end
    end

    context "when provided a non-business_plus Organization" do
      test "returns true when availability is all_accounts" do
        org = create :organization
        @report.all_accounts!

        refute_predicate org, :business_plus?
        assert_predicate @report, :all_accounts?
        assert @report.available_to?(org)
      end

      test "returns true when availability is ghec_accounts_only" do
        org = create :organization
        @report.ghec_accounts_only!

        refute_predicate org, :business_plus?
        assert_predicate @report, :ghec_accounts_only?
        refute @report.available_to?(org)
      end

      test "returns true when availability is non_ghec_accounts_only" do
        org = create :organization
        @report.non_ghec_accounts_only!

        refute_predicate org, :business_plus?
        assert_predicate @report, :non_ghec_accounts_only?
        assert @report.available_to?(org)
      end
    end
  end

  context "#to_s" do
    test "returns the report slug" do
      assert_equal @report.slug, @report.to_s
    end
  end

  context "#to_param" do
    test "returns the report slug" do
      assert_equal @report.slug, @report.to_param
    end
  end

  context "#description" do
    test "supports encoded characters" do
      report = create :compliance_report
      report.update! description: "Happy to help #{GRIN_EMOJI}"
      report.reload
      assert_equal "Happy to help #{GRIN_EMOJI}", report.description
    end
  end

  context "#download?" do
    test "returns true for downloads" do
      download = create :compliance_report, report_type: "download", filename: "whatever-lol.pdf"
      assert_predicate download, :download?
    end

    test "returns false for non-downloads" do
      link = create :compliance_report, report_type: "link", url: "https://whatever.lol"
      refute_predicate link, :download?
    end
  end

  context "#link?" do
    test "returns true for links" do
      link = create :compliance_report, report_type: "link", url: "https://whatever.lol"
      assert_predicate link, :link?
    end

    test "returns false for non-links" do
      download = create :compliance_report, report_type: "download", filename: "whatever-lol.pdf"
      refute_predicate download, :link?
    end
  end

  context "#group?" do
    test "returns true for groups" do
      group = create :compliance_report, report_type: "group"
      assert_predicate group, :group?
    end

    test "returns false for non-links" do
      download = create :compliance_report, report_type: "download", filename: "whatever-lol.pdf"
      refute_predicate download, :group?
    end
  end

  context "#child?" do
    test "returns true for child reports" do
      child = create :compliance_report,
        report_type: "download",
        filename: "whatever-lol.pdf",
        parent_id: @report.id
      assert_predicate child, :child?
    end

    test "returns false for non-child reports" do
      parent = create :compliance_report,
        report_type: "download",
        filename: "whatever-lol.pdf",
        parent_id: nil
      refute_predicate parent, :child?
    end
  end

  context "#child_reports" do
    test "returns empty for non group report" do
      refute_predicate @report, :group?
      assert_empty @report.child_reports
    end

    test "returns child reports for a group report ordered by display_order" do
      other = create :compliance_report
      group = create :compliance_report, report_type: "group"
      child_one = create :compliance_report, parent_id: group.id, display_order: 2
      child_two = create :compliance_report, parent_id: group.id, display_order: 1

      assert_predicate group, :group?
      assert_equal [child_two, child_one], group.child_reports
    end
  end

  context "#possible_parent_reports" do
    test "returns top level reports excluding self for persisted report" do
      another_top_level_report = create :compliance_report, report_type: "group"
      child_report = create :compliance_report, parent_id: another_top_level_report.id
      report = create :compliance_report

      assert_same_elements \
        [@report, another_top_level_report],
        report.possible_parent_reports
    end

    test "returns all top level reports for unpersisted report" do
      another_top_level_report = create :compliance_report, report_type: "group"
      child_report = create :compliance_report, parent_id: another_top_level_report.id
      report = create :compliance_report

      assert_same_elements \
        [@report, another_top_level_report, report],
        ComplianceReport.new.possible_parent_reports
    end
  end

  context "#storage" do
    test "uses Azure storage backend" do
      assert @report.storage.instance_of?(GHECAdmin::AzureStorage)
    end
  end
end
