# typed: true
# frozen_string_literal: true

require "test_helper"
require "ghec_admin"

class BusinessReportExportTest < GitHub::TestCase
  fixtures do
    @staffer = create(:staff_admin_user)
    @owner = create :user
    @business = create :business, owners: [@owner]
  end

  BusinessReportExport::REPORT_TYPES.each do |report_type|
    context "with #{report_type}" do
      test "validates report_type" do
        invalid_export = BusinessReportExport.new(report_type: "invalid")
        invalid_export.validate
        assert invalid_export.errors[:report_type].present?

        valid_export = BusinessReportExport.new(report_type: report_type)
        valid_export.validate
        refute valid_export.errors[:report_type].present?
      end

      test "#is_complete? returns true if completed_at is present" do
        export = @business.business_report_exports.create(actor: @owner, report_type: report_type)
        export.update(completed_at: Time.now)

        assert export.is_complete?
      end

      test "#is_complete? returns false if completed_at is missing" do
        export = @business.business_report_exports.create(actor: @owner, report_type: report_type)
        JobStatus.create(id: export.token)

        assert_nil export.completed_at
        refute export.is_complete?
      end

      test "#has_errored? returns true if errored_at is present" do
        export = @business.business_report_exports.create(actor: @owner, report_type: report_type)
        export.update(errored_at: Time.now)

        assert export.has_errored?
      end

      test "#has_errored? returns false if errored_at is missing" do
        export = @business.business_report_exports.create(actor: @owner, report_type: report_type)
        JobStatus.create(id: export.token)

        assert_nil export.errored_at
        refute export.has_errored?
      end

      test "supports an external staff actor" do
        on_multi_tenant_enterprise do
          emu_user = create :emu
          other_enterprise_emu_user = create :emu
          other_enterprise_emu_user.gh_role = "staff"
          other_enterprise_emu_user.save!

          GitHub::CurrentTenant.set(emu_user.enterprise_managed_business)

          export = emu_user.enterprise_managed_business.business_report_exports.create(actor: other_enterprise_emu_user, report_type: report_type)
          refute_nil export.actor
        end
      end

      test "does not support a generic external actor" do
        on_multi_tenant_enterprise do
          emu_user = create :emu
          other_enterprise_emu_user = create :emu

          GitHub::CurrentTenant.set(emu_user.enterprise_managed_business)

          export = emu_user.enterprise_managed_business.business_report_exports.create(actor: other_enterprise_emu_user, report_type: report_type)
          assert_nil export.actor
        end
      end

      test "#update_status successfully updates the status field on the report" do
        export = @business.business_report_exports.create(actor: @owner, report_type: report_type)
        export.update_status!(current_user_count: 1, total_user_count: 2)

        assert export.status, "1 / 2"
      end

      test "validates max 1 in progress" do
        export = @business.business_report_exports.create(actor: @owner, report_type: report_type)

        export.valid?(:create)
        assert export.errors[:base].present?

        export.update(completed_at: Time.now)
        export.valid?(:create)
        assert export.errors[:base].blank?
      end

      test "does not validate max 1 in progress on update" do
        export = @business.business_report_exports.create(actor: @owner, report_type: report_type)

        # Verify report is in progress
        assert report_type.constantize.in_progress_for_business?(business: @business)

        export.valid?(:update)
        assert export.errors[:base].blank?
      end

      test "requires an actor and an owner" do
        invalid_export = BusinessReportExport.new
        invalid_export.validate

        assert invalid_export.errors[:actor_id].present?
        assert invalid_export.errors[:owner_id].present?
        assert invalid_export.errors[:owner_type].present?
      end

      test "calls the #enqueue method of the appropriate report_type after create" do
        mock_report = mock(report_type)
        mock_report.stubs(:enqueue)
        report_type.constantize.stubs(:new).returns(mock_report)

        mock_report.expects(:enqueue)
        export = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business)
      end

      test "calls the #cleanup method of the appropriate report_type after destroy" do
        mock_report = mock(report_type)
        mock_report.stubs(:enqueue)
        report_type.constantize.stubs(:new).returns(mock_report)

        mock_report.expects(:cleanup)
        export = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business)
        export.destroy
      end

      test "sets settings to an empty hash if it is nil" do
        export = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business)
        assert_equal({}, export.settings)
      end

      test "does not override settings if it is already set" do
        export = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business, settings: { "foo" => "bar" })
        assert_equal({ "foo" => "bar" }, export.settings)
      end

      test "generates unique token for export request" do
        export = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business)

        assert export.token?, "expected token to be generated"
      end

      test "unique token generated doesn't clash with same export request" do
        export1 = create(:business_report_export, :completed, report_type: report_type, actor: @owner, owner: @business)
        export2 = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business)

        refute_equal export1.token, export2.token
      end

      test "returns token for parameter after validation" do
        export = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business)

        assert_predicate export, :valid?
        assert_equal export.to_param, export.token
      end

      test "responds to notify_when_complete" do
        export = create(:business_report_export, report_type: report_type, actor: @owner, owner: @business)

        refute_nil export.notify_when_complete?
      end
    end
  end

  context "for shared report types" do
    test "allows two different reports types to run simultaneously" do
      export_dormant = @business.business_report_exports.create(actor: @owner, report_type: "GHECAdmin::EnterpriseDormantUsersExport")
      # Cannot create a new export of the same type
      refute export_dormant.valid?(:create)

      export_enterprise = @business.business_report_exports.new(actor: @owner, report_type: "GHECAdmin::EnterpriseUsersExport")
      # Can create a new export of a different type
      assert export_enterprise.valid?(:create)
    end
  end
end
