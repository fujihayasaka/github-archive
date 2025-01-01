# typed: true
# frozen_string_literal: true

require "test_helper"

class QuantileTest < GitHub::TestCase
  context "creating a quantile" do
    test "sorts the domain values" do
      domain = [3, 2, 4, 1, 2, 1]
      subject = Quantile.new(domain: domain, range: %w[a b c])
      assert_equal [1, 1, 2, 2, 3, 4], subject.domain
      assert_equal [3, 2, 4, 1, 2, 1], domain
    end
  end

  context "ranking values" do
    test "handles even-sized sets" do
      values = [3, 6, 7, 8, 8, 10, 13, 15, 16, 20]
      subject = Quantile.new(domain: values, range: %w[a b c d])
      assert_equal "a", subject.scale(3)
      assert_equal "b", subject.scale(9)
      assert_equal "c", subject.scale(13)
      assert_equal "d", subject.scale(15)
      assert_equal "d", subject.scale(16)
    end

    test "handles odd-sized sets" do
      values = [3, 6, 7, 8, 8, 9, 10, 13, 15, 16, 20]
      subject = Quantile.new(domain: values, range: %w[a b c d])
      assert_equal "a", subject.scale(3)
      assert_equal "b", subject.scale(9)
      assert_equal "c", subject.scale(13)
      assert_equal "d", subject.scale(15)
      assert_equal "d", subject.scale(16)
    end
  end

  context "determining n-sized quantiles" do
    test "handles even-sized sets" do
      values = [3, 6, 7, 8, 8, 10, 13, 15, 16, 20]
      subject = Quantile.new(domain: values, range: %w[a b c d])
      assert_equal 0, subject.n_quantile(3)
      assert_equal 1, subject.n_quantile(9)
      assert_equal 2, subject.n_quantile(13)
      assert_equal 3, subject.n_quantile(15)
      assert_equal 3, subject.n_quantile(16)
    end

    test "handles odd-sized sets" do
      values = [3, 6, 7, 8, 8, 9, 10, 13, 15, 16, 20]
      subject = Quantile.new(domain: values, range: %w[a b c d])
      assert_equal 0, subject.n_quantile(3)
      assert_equal 1, subject.n_quantile(9)
      assert_equal 2, subject.n_quantile(13)
      assert_equal 3, subject.n_quantile(15)
      assert_equal 3, subject.n_quantile(16)
    end
  end
end
