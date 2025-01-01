# typed: true
# frozen_string_literal: true

require "test_helper"

class EmailDomainReputationRecordTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    EmailDomainReputationRecord.clear_caches
  end

  context ".metadata" do
    test "returns all associated email domains, mx exchanges, and A records" do
      create(:email_domain_reputation_record, {
        email_domain: "okstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
      })
      create(:email_domain_reputation_record, {
        email_domain: "okstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
      })
      create(:email_domain_reputation_record, {
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
      })
      create(:email_domain_reputation_record, {
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
      })

      expected = {
        email_domains: ["connorsstate.edu", "okstate.edu"],
        mx_exchanges: ["mailhost07.okstate.edu", "mailhost08.okstate.edu"],
        a_records: ["139.78.133.12", "139.78.133.13"],
        has_valid_public_suffix: true,
      }

      assert_equal expected, EmailDomainReputationRecord.metadata("sam@okstate.edu")
    end

    test "returns associated records for mx_exchange address_type" do
      create(:email_domain_reputation_record, {
        email_domain: "okstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
      })
      create(:email_domain_reputation_record, {
        email_domain: "okstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
      })
      create(:email_domain_reputation_record, {
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
      })
      create(:email_domain_reputation_record, {
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
      })

      expected = {
        email_domains: ["connorsstate.edu", "okstate.edu"],
        mx_exchanges: ["mailhost07.okstate.edu", "mailhost08.okstate.edu"],
        a_records: ["139.78.133.12", "139.78.133.13"],
        has_valid_public_suffix: nil,
      }

      assert_equal expected, EmailDomainReputationRecord.metadata("mailhost07.okstate.edu", address_type: :mx_exchange)
    end

    test "returns associated records for a_records address_type" do
      create(:email_domain_reputation_record, {
        email_domain: "okstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
      })
      create(:email_domain_reputation_record, {
        email_domain: "okstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
      })
      create(:email_domain_reputation_record, {
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
      })
      create(:email_domain_reputation_record, {
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
      })

      expected = {
        email_domains: ["connorsstate.edu", "okstate.edu"],
        mx_exchanges: ["mailhost07.okstate.edu", "mailhost08.okstate.edu"],
        a_records: ["139.78.133.12", "139.78.133.13"],
        has_valid_public_suffix: nil,
      }

      assert_equal expected, EmailDomainReputationRecord.metadata("139.78.133.12", address_type: :a_record)
    end

    test "has_valid_public_suffix is false when suffix is invalid" do
      expected = {
        email_domains: [],
        mx_exchanges: [],
        a_records: [],
        has_valid_public_suffix: false,
      }

      assert_equal expected, EmailDomainReputationRecord.metadata("foo@abc.invalidSuffix")
    end

    test "raises InvalidAddressType for unknown address type" do
      assert_raises(EmailDomainReputationRecord::InvalidAddressType) do
        EmailDomainReputationRecord.metadata("foo.bar", address_type: :foo)
      end
    end
  end

  context ".reputation" do
    test "returns reputation for domain when it exists" do
      record = create(:email_domain_reputation_record, sample_size: 10, not_spammy_sample_size: 9)
      reputation = EmailDomainReputationRecord.reputation(record.email_domain)
      assert_equal 0.9, reputation.reputation
      assert_equal 0.5959, reputation.reputation_lower_bound
      assert_equal 10, reputation.sample_size
      assert_equal 9, reputation.not_spammy_sample_size
      assert_equal :low, reputation.warning_level
    end

    test "returns reputation for mx_exchange when it exists" do
      record = create(:email_domain_reputation_record, sample_size: 10, not_spammy_sample_size: 9)
      reputation = EmailDomainReputationRecord.reputation(record.mx_exchange, address_type: :mx_exchange)
      assert_equal 0.9, reputation.reputation
      assert_equal 0.5959, reputation.reputation_lower_bound
      assert_equal 10, reputation.sample_size
      assert_equal 9, reputation.not_spammy_sample_size
    end

    test "returns reputation for a_record when it exists" do
      record = create(:email_domain_reputation_record, sample_size: 10, not_spammy_sample_size: 9)
      reputation = EmailDomainReputationRecord.reputation(record.a_record, address_type: :a_record)
      assert_equal 0.9, reputation.reputation
      assert_equal 0.5959, reputation.reputation_lower_bound
      assert_equal 10, reputation.sample_size
      assert_equal 9, reputation.not_spammy_sample_size
    end

    test "raises InvalidAddressType for unknown address type" do
      assert_raises(EmailDomainReputationRecord::InvalidAddressType) do
        EmailDomainReputationRecord.reputation("foo.bar", address_type: :foo)
      end
    end

    test "returns default reputation when sample_size is 0" do
      record = create(:email_domain_reputation_record, sample_size: 0, not_spammy_sample_size: 0)
      reputation = EmailDomainReputationRecord.reputation(record.email_domain)

      assert_equal 1.0, reputation.reputation
      assert_equal 1.0, reputation.reputation_lower_bound
      assert_equal 0, reputation.sample_size
      assert_equal 0, reputation.not_spammy_sample_size
    end

    test "returns default reputation for domain when it does not exist" do
      reputation = EmailDomainReputationRecord.reputation("okstate.edu")
      assert_equal 1.0, reputation.reputation
      assert_equal 1.0, reputation.reputation_lower_bound
      assert_equal 0, reputation.sample_size
      assert_equal 0, reputation.not_spammy_sample_size
    end

    test "returns critical reputation for domain when it exists" do
      record = create(:email_domain_reputation_record, sample_size: 10, not_spammy_sample_size: 2)
      reputation = EmailDomainReputationRecord.reputation(record.email_domain)
      assert_equal 0.2, reputation.reputation
      assert_equal 0.0567, reputation.reputation_lower_bound
      assert_equal 10, reputation.sample_size
      assert_equal 2, reputation.not_spammy_sample_size
      assert_equal :critical, reputation.warning_level
    end

    test "returns warning reputation for domain when it exists" do
      record = create(:email_domain_reputation_record, sample_size: 10, not_spammy_sample_size: 3)
      reputation = EmailDomainReputationRecord.reputation(record.email_domain)
      assert_equal 0.3, reputation.reputation
      assert_equal 0.1078, reputation.reputation_lower_bound
      assert_equal 10, reputation.sample_size
      assert_equal 3, reputation.not_spammy_sample_size
      assert_equal :warning, reputation.warning_level
    end
  end

  context ".exists?" do
    test "returns true if the email domain reputation records exist for this domain" do
      create(:email_domain_reputation_record, email_domain: "foo.bar")
      assert EmailDomainReputationRecord.exists?("jonmagic@foo.bar")
    end

    test "returns false if no email domain reputation records exists for this domain" do
      refute EmailDomainReputationRecord.exists?("jonmagic@foo.bar")
    end
  end

  context ".recent_users" do
    test "it returns no more than the limit sorted newest to oldest" do
      oldest_user = create(:user, email: "oldest@foo.bar")
      middle_user = create(:user, email: "middle@foo.bar")
      newest_user = create(:user, email: "newest@foo.bar")
      users = EmailDomainReputationRecord.recent_users("foo.bar", limit: 2)

      assert_equal 2, users.size
      refute_includes users, oldest_user
      assert_includes users, middle_user
      assert_includes users, newest_user
    end
  end

  context ".process" do
    test "creates records for domain" do
      GitHub.flipper[:email_domain_reputation_record].enable

      bob = create(:user, email: "bob@okstate.edu")
      pam = create(:spammy_user, email: "pam@okstate.edu")
      jon = create(:spammy_user, email: "jon@okstate.edu")
      nat = create(:spammy_user, email: "nat@connorsstate.edu")
      EmailDomainReputationRecord.expects(:lookup_mx_records).with("okstate.edu").returns([
        "mailhost07.okstate.edu",
        "mailhost08.okstate.edu",
      ])
      EmailDomainReputationRecord.expects(:lookup_mx_records).with("connorsstate.edu").returns([
        "mailhost07.okstate.edu",
        "mailhost08.okstate.edu",
      ])
      EmailDomainReputationRecord.expects(:lookup_a_records).with("mailhost07.okstate.edu").twice.returns([
        "139.78.133.12",
      ])
      EmailDomainReputationRecord.expects(:lookup_a_records).with("mailhost08.okstate.edu").twice.returns([
        "139.78.133.13",
      ])
      EmailDomainReputationRecord.expects(:calculation_ms).twice.returns(1234).then.returns(4321)

      EmailDomainReputationRecord.process("bob@okstate.edu")

      assert_equal 2, EmailDomainReputationRecord.count
      assert_predicate EmailDomainReputationRecord.where({
        email_domain: "okstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
        sample_size: 3,
        not_spammy_sample_size: 1,
      }), :exists?
      assert_predicate EmailDomainReputationRecord.where({
        email_domain: "okstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
        sample_size: 3,
        not_spammy_sample_size: 1,
      }), :exists?
      unless GitHub.enterprise?
        assert_hydro_published({
          domain: "okstate.edu",
          recent_users: [
            Hydro::EntitySerializer.user(bob),
            Hydro::EntitySerializer.user(pam),
            Hydro::EntitySerializer.user(jon),
          ],
          sample_size: 3,
          not_spammy_sample_size: 1,
          spammy_sample_size: 2,
          reputation: 0.3333333432674408,
          reputation_lower_bound: 0.061500001698732376,
          plus_minus: 0.5334335565567017,
          maximum_reputation: 0.8667668700218201,
          minimum_reputation: 0,
          email_domains: ["okstate.edu"],
          mx_exchanges: ["mailhost07.okstate.edu", "mailhost08.okstate.edu"],
          a_records: ["139.78.133.12", "139.78.133.13"],
          has_valid_public_suffix: true,
          calculation_ms: 1234,
        }, schema: "github.v1.EmailDomainReputationRecordCreate")
      end

      EmailDomainReputationRecord.process("nat@connorsstate.edu")

      assert_equal 4, EmailDomainReputationRecord.count
      assert_predicate EmailDomainReputationRecord.where({
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost07.okstate.edu",
        a_record: "139.78.133.12",
        sample_size: 4,
        not_spammy_sample_size: 1,
      }), :exists?
      assert_predicate EmailDomainReputationRecord.where({
        email_domain: "connorsstate.edu",
        mx_exchange: "mailhost08.okstate.edu",
        a_record: "139.78.133.13",
        sample_size: 4,
        not_spammy_sample_size: 1,
      }), :exists?
      unless GitHub.enterprise?
        assert_hydro_published({
          domain: "connorsstate.edu",
          recent_users: [
            Hydro::EntitySerializer.user(nat),
          ],
          sample_size: 4,
          not_spammy_sample_size: 1,
          spammy_sample_size: 3,
          reputation: 0.25,
          reputation_lower_bound: 0.04560000076889992,
          plus_minus: 0.4243437945842743,
          maximum_reputation: 0.6743437647819519,
          minimum_reputation: 0.0,
          email_domains: ["connorsstate.edu", "okstate.edu"],
          mx_exchanges: ["mailhost07.okstate.edu", "mailhost08.okstate.edu"],
          a_records: ["139.78.133.12", "139.78.133.13"],
          has_valid_public_suffix: true,
          calculation_ms: 4321,
        }, schema: "github.v1.EmailDomainReputationRecordCreate")
      end
    end

    test "creates records for domain if mx exchange does not exist but A record does" do
      GitHub.flipper[:email_domain_reputation_record].enable

      EmailDomainReputationRecord.stubs(:lookup_a_records).returns(["10.0.1.123"])
      EmailDomainReputationRecord.expects(:lookup_mx_records).with("abc.bg.com").returns([])
      EmailDomainReputationRecord.expects(:lookup_mx_records).with("bcd.bg.com").returns([])
      EmailDomainReputationRecord.expects(:lookup_mx_records).with("cde.bg.com").returns([])

      bg1 = create(:spammy_user, email: "bg1@abc.bg.com")
      EmailDomainReputationRecord.process("bg1@abc.bg.com")

      bg2 = create(:spammy_user, email: "bg2@bcd.bg.com")
      EmailDomainReputationRecord.process("bg2@bcd.bg.com")

      bg3 = create(:spammy_user, email: "bg3@cde.bg.com")
      EmailDomainReputationRecord.process("bg3@cde.bg.com")

      assert_equal 3, EmailDomainReputationRecord.count

      assert_predicate EmailDomainReputationRecord.where({
        a_record: "10.0.1.123",
        sample_size: 3,
        not_spammy_sample_size: 0,
      }), :exists?
    end
  end

  context ".process_later" do
    test "calls ProcessEmailDomainForReputationDataJob.perform_later with domain" do
      GitHub.flipper[:email_domain_reputation_record].enable
      domain = "foo.com"
      ProcessEmailDomainForReputationDataJob.expects(:perform_later).with(domain)
      EmailDomainReputationRecord.process_later(domain)
    end
  end

  context ".sample_sizes_for_domains" do
    test "returns array with not_spammy_sample_size and sample_size" do
      UserEmail.connection.stubs(:select_rows).returns([[1, 2, 3]])
      User.connection.stubs(:select_rows).returns([[1, 2]])

      assert_equal [1, 2], EmailDomainReputationRecord.sample_sizes_for_domains("foo.bar")
    end

    test "handles select_rows array that is empty" do
      UserEmail.connection.stubs(:select_rows).returns([[1, 2, 3]])
      User.connection.stubs(:select_rows).returns([[]])

      assert_equal [0, 0], EmailDomainReputationRecord.sample_sizes_for_domains("foo.bar")
    end

    test "handles select_rows array with a nil value" do
      UserEmail.connection.stubs(:select_rows).returns([[1, 2, 3]])
      User.connection.stubs(:select_rows).returns([[nil, 0]])

      assert_equal [0, 0], EmailDomainReputationRecord.sample_sizes_for_domains("foo.bar")
    end

    test "handles empty user_ids array" do
      UserEmail.connection.stubs(:select_rows).returns([[]])

      assert_equal [0, 0], EmailDomainReputationRecord.sample_sizes_for_domains("foo.bar")
    end
  end

  context ".lookup_mx_records" do
    test "memoizes lookups" do
      EmailDomainReputationRecord::DNS_RESOLVER.
        expects(:getresources).
        with("foo.bar", Resolv::DNS::Resource::IN::MX).
        once.
        returns([stub(exchange: stub(to_s: "mail.foo.bar"))])

      assert_equal ["mail.foo.bar"], EmailDomainReputationRecord.lookup_mx_records("foo.bar")
      assert_equal ["mail.foo.bar"], EmailDomainReputationRecord.lookup_mx_records("foo.bar")
    end
  end

  context ".lookup_a_records" do
    test "memoizes lookups" do
      EmailDomainReputationRecord::DNS_RESOLVER.
        expects(:getresources).
        with("mail.foo.bar", Resolv::DNS::Resource::IN::A).
        once.
        returns([stub(address: stub(to_s: "1.2.3.4"))])

      assert_equal ["1.2.3.4"], EmailDomainReputationRecord.lookup_a_records("mail.foo.bar")
      assert_equal ["1.2.3.4"], EmailDomainReputationRecord.lookup_a_records("mail.foo.bar")
    end
  end
end
