# typed: strict
# frozen_string_literal: true

require "test_helper"

class GitignoreTest < GitHub::TestCase
  setup do
    stub_templates = %w[Perl Python Ruby]
    Gitignore.stubs(:templates).returns(stub_templates)
  end

  test ".template_exists?" do
    assert Gitignore.template_exists?("Ruby")
    assert_equal false, Gitignore.template_exists?("None")
  end
end
