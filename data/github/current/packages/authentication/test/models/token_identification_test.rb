# typed: true
# frozen_string_literal: true

require "test_helper"

class TokenIdentificiationTest < GitHub::TestCase
  setup do
    enable_feature_flag(:credential_revocation_api)
  end

  context "#identify_tokens" do
    test "no tokens" do
      identified_tokens = TokenIdentification.identify_tokens([])
      refute identified_tokens.key?(TokenRevocation::Helper::PAT_CREDENTIAL)
      refute identified_tokens.key?(TokenRevocation::Helper::FG_PAT_CREDENTIAL)
      refute identified_tokens.key?(:UNKNOWN)
    end

    context "single token" do
      test "PAT" do
        tokens = generate_pats(1)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal 1, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_empty identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "old FG-PAT" do
        tokens = generate_old_fg_pats(1)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_equal 1, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "FG-PAT" do
        tokens = generate_fg_pats(1)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_equal 1, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "unknown" do
        tokens = generate_fake_tokens(1)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_empty identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        assert_equal 1, T.must(identified_tokens[:UNKNOWN]).size
      end

      test "combination of PATs, FG-PATs and unknown" do
        tokens = (generate_fake_tokens(1) + generate_pats(1) + generate_fg_pats(1)).shuffle
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal 1, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_equal 1, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_equal 1, T.must(identified_tokens[:UNKNOWN]).size
      end
    end

    context "multiple tokens" do
      test "100 PATs" do
        tokens = generate_pats(100)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal 100, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_empty identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "100 FG-PATs" do
        tokens = generate_fg_pats(100)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_equal 100, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "100 unknown" do
        tokens = generate_fake_tokens(100)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_empty identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        assert_equal 100, T.must(identified_tokens[:UNKNOWN]).size
      end

      test "combination of PATs and unknown" do
        num_of_pats = rand(1..200)
        num_of_unknowns = rand(1..200)
        tokens = (generate_pats(num_of_pats) + generate_fake_tokens(num_of_unknowns)).shuffle
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal num_of_pats, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_empty identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        assert_equal num_of_unknowns, T.must(identified_tokens[:UNKNOWN]).size
      end

      test "combination of FG-PATs and unknown" do
        num_of_fg_pats = rand(1..200)
        num_of_unknowns = rand(1..200)
        tokens = (generate_fg_pats(num_of_fg_pats) + generate_fake_tokens(num_of_unknowns)).shuffle
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_equal num_of_fg_pats, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_equal num_of_unknowns, T.must(identified_tokens[:UNKNOWN]).size
      end

      test "combination of PATs and FG-PATs" do
        num_of_pats = rand(1..200)
        num_of_fg_pats = rand(1..200)
        tokens = (generate_pats(num_of_pats) + generate_fg_pats(num_of_fg_pats)).shuffle
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal num_of_pats, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_equal num_of_fg_pats, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "combination of PATs, FG-PATs and unknown" do
        num_of_pats = rand(1..200)
        num_of_fg_pats = rand(1..200)
        num_of_unknowns = rand(1..200)
        tokens = (generate_pats(num_of_pats) + generate_fg_pats(num_of_fg_pats) + generate_fake_tokens(num_of_unknowns)).shuffle
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal num_of_pats, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_equal num_of_fg_pats, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_equal num_of_unknowns, T.must(identified_tokens[:UNKNOWN]).size
      end
    end

    context "max input" do
      test "all PATs" do
        tokens = generate_pats(1000)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal 1000, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_empty identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "all FG-PATs" do
        tokens = generate_fg_pats(1000)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_equal 1000, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_empty identified_tokens[:UNKNOWN]
      end

      test "all unknown" do
        tokens = generate_fake_tokens(1000)
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_empty identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        assert_empty identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        assert_equal 1000, T.must(identified_tokens[:UNKNOWN]).size
      end

      test "combination of PATs, FG-PATs and unknown" do
        number_of_pats = 400
        number_of_fg_pats = 400
        number_of_unknowns = 200

        tokens = (generate_pats(number_of_pats) + generate_fg_pats(number_of_fg_pats) + generate_fake_tokens(number_of_unknowns)).shuffle
        identified_tokens = TokenIdentification.identify_tokens(tokens)
        assert_equal number_of_pats, T.must(identified_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]).size
        assert_equal number_of_fg_pats, T.must(identified_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]).size
        assert_equal number_of_unknowns, T.must(identified_tokens[:UNKNOWN]).size
      end
    end

    context "#identify_token" do
      test "returns nil if token is not recognized" do
        fake_pat = "ghp_#{SecureRandom.alphanumeric(34)}"
        assert_nil TokenIdentification.identify_token(fake_pat)
      end

      test "returns nil if token is not supported" do
        s2s_token = "ghs_#{SecureRandom.alphanumeric(36)}"
        assert_nil TokenIdentification.identify_token(s2s_token)
      end

      test "returns PAT if token is a PAT" do
        pat = generate_pats(1).first
        assert_equal TokenRevocation::Helper::PAT_CREDENTIAL, TokenIdentification.identify_token(pat)
      end

      test "returns FG-PAT if token is the old FG-PAT version" do
        fg_pat = generate_old_fg_pats(1).first
        assert_equal TokenRevocation::Helper::FG_PAT_CREDENTIAL, TokenIdentification.identify_token(fg_pat)
      end

      test "returns FG-PAT if token is a FG-PAT" do
        fg_pat = generate_fg_pats(1).first
        assert_equal TokenRevocation::Helper::FG_PAT_CREDENTIAL, TokenIdentification.identify_token(fg_pat)
      end

      test "returns FG-PAT if FG-PAT token contains PAT prefix" do
        # there is a ghp_ in the middle of the bogus token
        fg_pat = "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"
        assert_equal TokenRevocation::Helper::FG_PAT_CREDENTIAL, TokenIdentification.identify_token(fg_pat)
      end

      test "returns FG-PAT if old FG-PAT token contains PAT prefix" do
        # there is a ghp_ in the middle of the bogus token
        fg_pat = "gh1_FRKFYlMu84CoKW2xV5ghp_QsZZcDQFY1F7Ip1QqXBznnAD0gA88gXPsjUhBGWpi18ve3II4byJPUJjAlu"
        assert_equal TokenRevocation::Helper::FG_PAT_CREDENTIAL, TokenIdentification.identify_token(fg_pat)
      end
    end
  end

  private

  def generate_pats(num_of_times)
    pats = []
    num_of_times.times do
      pats << "ghp_#{SecureRandom.alphanumeric(36)}"
    end
    pats
  end

  def generate_fg_pats(num_of_times)
    fg_pats = []
    num_of_times.times do |idx|
      # alternate between the two formats
      if idx % 2 == 0
        fg_pats << "github_pat_1#{SecureRandom.alphanumeric(21)}_#{SecureRandom.alphanumeric(59)}"
      else
        fg_pats << "gh1_#{SecureRandom.alphanumeric(21)}_#{SecureRandom.alphanumeric(59)}"
      end
    end
    fg_pats
  end

  def generate_old_fg_pats(num_of_times)
    fg_pats = []
    num_of_times.times do
      fg_pats << "gh1_#{SecureRandom.alphanumeric(21)}_#{SecureRandom.alphanumeric(59)}"
    end
    fg_pats
  end

  def generate_fake_tokens(num_of_times)
    fake_tokens = []
    num_of_times.times do |idx|
      fake_tokens << "fake_tokens_#{idx}"
    end
    fake_tokens
  end
end
