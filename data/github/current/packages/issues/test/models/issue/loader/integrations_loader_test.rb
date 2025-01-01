# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class IntegrationsLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @integration1 = create(:integration, name: "app1")
    @integration2 = create(:integration, name: "app2")
    @issue1 = create(:issue, repository: @repository, performed_via_integration: @integration1)
    @issue2 = create(:issue, repository: @repository, performed_via_integration: @integration1)
    @issue3 = create(:issue, repository: @repository, performed_via_integration: @integration2)
    @issue4 = create(:issue, repository: @repository)

    # reload issues to make sure nothing is preloaded
    @issue1, @issue2, @issue3, @issue4 = Issue.find(@issue1.id), Issue.find(@issue2.id), Issue.find(@issue3.id), Issue.find(@issue4.id)

    @models = [@issue1, @issue2, @issue3, @issue4]
  end

  setup do
    @context = Issue::Adapter::Context.new(@issue1, @repository, @user, cap_filter: cap_authorizing_filter)
    Issue::Loader::CurrentIssue.load_for(@context)
    Issue::Loader::CurrentRepository.load_for(@context)
  end

  test "loading integrations only executes expected queries" do
    result, queries = log_queries do
      Issue::Loader::Integrations.load_for(@context, integration_ids: @models.map(&:performed_by_integration_id))
    end

    # 1 query for loading all integrations (... WHERE `integrations`.`id` IN (23, 24))
    expected_count = 1
    assert_equal expected_count, queries.count

    # adds integrations to @context
    assert_equal 2, @context.integrations.size

    assert @context.integrations.include?(@issue1.performed_via_integration)
    assert @context.integrations.include?(@issue2.performed_via_integration)
    assert @context.integrations.include?(@issue3.performed_via_integration)
    refute @context.integrations.include?(@issue4.performed_via_integration)

    assert_equal @integration1.id, @context.integrations_by_id[@issue1.performed_via_integration.id].id
    assert_equal @integration1.id, @context.integrations_by_id[@issue2.performed_via_integration.id].id
    assert_equal @integration2.id, @context.integrations_by_id[@issue3.performed_via_integration.id].id
  end
end
