# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountTest < GitHub::TestCase
  context "subclasses consistently" do
    test "define a unique key" do
      duplicates = SocialAccount.all_providers.group_by(&:key).select { |_, providers| providers.size > 1 }
      if duplicates.any?
        msg = "Duplicate social account provider keys found! Each provider must override .key " \
          "to return a unique String.\n\n".dup
        duplicates.each do |key, providers|
          msg << " #{key.inspect} is shared by #{providers.map(&:name).join(", ")}\n"
        end
        flunk msg
      end
    end

    test "define exactly one of .octicon_name and .svg_path" do
      invalid = []
      SocialAccount.all_providers.each do |provider|
        reason = "both" if provider.octicon_name.present? && provider.svg_path.present?
        reason = "neither" if provider.octicon_name.nil? && provider.svg_path.nil?
        invalid << [provider, reason] if reason
      end

      if invalid.any?
        msg = "Social account providers must define exactly one of .octicon_name or .svg_path " \
          "to return a non-empty value.\n\n".dup
        invalid.each do |provider, reason|
          msg << "  #{provider} defines #{reason}.\n"
        end
        flunk msg
      end
    end

    test "define .svg_paths to svgs that actually exist" do
      invalid = []
      SocialAccount.all_providers.each do |provider|
        svg_path = provider.svg_path
        next unless svg_path

        invalid << provider unless File.exist?(Rails.root.join("public/images/modules/#{svg_path}.svg"))
      end

      if invalid.any?
        msg = "These social account providers define .svg_path to return a value that does not " \
          "exist in the public/images/modules/site/icons directory.\n\n".dup
        invalid.each do |provider|
          msg << "  #{provider} - #{provider.svg_path.inspect}\n"
        end
        flunk msg
      end
    end
  end

  context "encode and extract" do
    test "round trips data successfully" do
      accounts = [
        SocialAccounts::LinkedIn.new(url: "https://www.linkedin.com/in/monalisa"),
        SocialAccounts::Mastodon.new(
          url: "https://subdomain.mastodon.social/@monalisa",
          meta: { "name_override" => "@monalisa@mastodon.social" },
        ),
        SocialAccounts::Twitter.new(url: "https://twitter.com/monalisa"),
        SocialAccounts::Generic.new(url: "https://example.com/monalisa"),
      ]

      encoded = accounts.map(&:encode)
      extracted = SocialAccount.extract(encoded)

      assert_equal accounts.size, extracted.size
      accounts.zip(extracted).each do |account_in, account_out|
        assert_equal account_in.class, account_out.class
        assert_equal account_in.url, T.must(account_out).url
        assert_equal account_in.meta, T.must(account_out).meta
      end
    end

    test "ignores invalid top-level structure" do
      assert_empty SocialAccount.extract({ nope: 1234 })
    end

    test "skips a hash without a key" do
      assert_empty SocialAccount.extract([{ "url" => "https://example.com" }])
    end

    test "skips a hash without a URL" do
      assert_empty SocialAccount.extract([{ "key" => "twitter" }])
    end

    test "skips an invalid key type" do
      assert_empty SocialAccount.extract([{ "key" => 1234, "url" => "https://example.com" }])
    end

    test "skips an invalid URL type" do
      assert_empty SocialAccount.extract([{ "key" => "twitter", "url" => { something: 4321 } }])
    end

    test "skips an invalid meta type" do
      accounts = SocialAccount.extract([{ "key" => "mastodon", "url" => "https://example.com", "meta" => 1234 }])
      assert_empty accounts.sole.meta
    end

    test "falls back to generic for unrecognized keys" do
      accounts = SocialAccount.extract([{ "key" => "wut", "url" => "https://example.com" }])
      assert_equal 1, accounts.size
      assert_equal SocialAccounts::Generic, accounts.first.class
    end
  end

  context "equality" do
    test "is equal to another account of the same kind with the same URL" do
      a, b = create_pair(:social_account_twitter)

      assert_equal a, b
      assert_equal a.hash, b.hash
    end

    test "is not equal to another account of the same kind with a different URL" do
      a = create(:social_account_twitter, url: "https://twitter.com/monalisa")
      b = create(:social_account_twitter, url: "https://twitter.com/monalisa2")

      refute_equal a, b
    end

    test "is not equal to another account of a different kind with the same URL" do
      a = create(:social_account_twitter)
      b = create(:social_account, url: a.url)

      refute_equal a, b
    end

    test "is equal to another account with different meta" do
      a = create(:social_account_mastodon, meta: { "something" => "aaa" })
      b = create(:social_account_mastodon, meta: { "other" => "bbb" })

      assert_equal a, b
    end
  end

  context "with_name_override" do
    test "overrides the formatted display name on the returned instance" do
      original = create(:social_account, url: "https://original.com/monalisa")
      assert_equal "https://original.com/monalisa", original.format_account_name

      overridden = original.with_name_override("overridden")
      assert_equal "https://original.com/monalisa", overridden.url
      assert_equal "overridden", overridden.format_account_name
    end
  end
end
