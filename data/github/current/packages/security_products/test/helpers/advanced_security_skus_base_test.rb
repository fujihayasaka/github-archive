# typed: true
# frozen_string_literal: true

require "test_helpers/advanced_security/advanced_security_skus_test_helper"

# AdvancedSecuritySKUsBaseTest provides a test-creation method, `skus_test`,
# which acts as a drop-in replacement for ActiveSupport's `test` method.
#
# `skus_test` creates _two_ test methods, one which runs with bundled SKU
# settings and one with unbundled SKU settings.
#
# The selection of these settings is done by the other methods in this class,
# `do_purchase` and `enable_service`. These should be called in your test blocks
# instead of directly calling the methods which they use.
#
# Classes which inherit from this one automatically have an additional setup step,
# enabling or disabling a feature flag depending on the type of SKU test being run
# (or doing the equivalent licence setting on GHES).
class AdvancedSecuritySKUsBaseTest < GitHub::TestCase
  extend T::Helpers

  abstract!

  include AdvancedSecuritySKUsTestHelper

  sig { params(repo: Repository, actor: User).void }
  def enable_service(repo, actor:)
    if split_sku_test?
      SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_enable: [[:code_security, { force?: true }]])
    else
      SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_enable: [[:advanced_security, { force?: true }]])
    end
  end

  sig { params(args: T.untyped, block: T.proc.bind(T.attached_class).void).void }
  def self.setup(*args, &block)
    super(*T.unsafe(args)) do
      T.bind(self, T.attached_class) # we're in a class method, but this block is run in an instance method context

      if split_sku_test?
        # When this feature flag is enabled on a repo, we pretend that the repo has "actions" code, even if it doesn't.
        # We'll be refining this before we roll that flag out broadly, so for now we'll test with the flag disabled so that
        # our tests that expect no languages to be detected still pass.
        disable_feature_flag(:code_scanning_actions_analysis)

        GitHub::Enterprise.license.stubs(:code_security_enabled).returns(true) if GitHub.enterprise?
      end

      instance_eval(&block)
    end
  end

  sig { params(name: String, opts: T::Hash[Symbol, T.untyped], block: T.proc.bind(T.attached_class).void).void }
  def self.skus_test(name, opts = {}, &block)
    # You should avoid wrapping `&block` to add functionality here: The resulting block
    # will have a different source location, so the tests won't be invokable by file and line number.
    # Instead, add to `setup` above, or create a new method like `do_purchase` or `enable_sku` and
    # call that in your test block.
    test("#{name} #{BUNDLED_TEST_SUFFIX}", opts, &block)
    test("#{name} #{UNBUNDLED_TEST_SUFFIX}", opts, &block)
  end
end
