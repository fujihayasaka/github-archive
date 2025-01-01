# typed: true
# frozen_string_literal: true
require "test_helper"

class DsaExplanationsTest < ActiveSupport::TestCase

  def test_email_partial_for_tos_reason_returns_the_correct_partial_for_a_tos_reason
    assert_equal "our Acceptable Use Policy prohibiting threats of violence and gratuitously violent content. You may not use GitHub to organize, promote, encourage, threaten, or incite acts of violence. You may not post content that depicts or glorifies violence or physical harm against human beings or animals.", DsaExplanations.email_partial_for_tos_reason("VIOLENT_CONTENT")
  end

  def test_email_partial_for_tos_reason_returns_a_reasonable_fallback_if_no_email_partial_is_found_for_supplied_tos_reason
    assert_equal "our Acceptable Use Policies or Terms of Service.", DsaExplanations.email_partial_for_tos_reason("ASDFGHJKL")
  end

  def test_email_partial_for_dsa_source_returns_the_correct_partial_for_a_dsa_source
    assert_equal "we received a notification from our automated scanning systems", DsaExplanations.email_partial_for_dsa_source("SCAN_DETECTION")
  end

  def test_email_partial_for_dsa_source_returns_a_reasonable_fallback_if_no_email_partial_is_found_for_supplied_dsa_source
    assert_equal "we reviewed your account", DsaExplanations.email_partial_for_dsa_source("QWERTYUIOP")
  end

  def test_fallbacks_for_email_partials_combined_make_sense
    assert_equal "This moderation action was taken after we reviewed your account and determined that your account violates our Acceptable Use Policies or Terms of Service.", "This moderation action was taken after #{DsaExplanations.email_partial_for_dsa_source("QWERTYUIOP")} and determined that your account violates #{DsaExplanations.email_partial_for_tos_reason("ASDFGHJKL")}"
  end
end
