# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesLabelQueryTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @repo = create(:private_repository)
    @user = @repo.owner
  end

  setup do
    setup_search
    @query = Search::Queries::LabelQuery.new(current_user: @user, repo_id: @repo.id)
  end

  teardown_once do
    teardown_search
  end

  context "query params" do
    test "it will query labels" do
      assert_equal({ type: "label", routing: @repo.id }, @query.query_params)
    end
  end

  test "it highlights searched fields" do
    @query.phrase = "search"
    expected = {
      encoder: :html,
      require_field_match: true,
      fields: {
        "name.ngram" => { number_of_fragments: 0 },
        :name => { number_of_fragments: 0 },
        :description => { number_of_fragments: 1, fragment_size: 200 },
      },
      type: "plain"
    }

    assert_equal expected, @query.build_highlight
  end

  context "when building the sort" do
    test "returns nil when the sort is empty and a query is present" do
      @query.query = "foo"
      assert_nil @query.build_sort
    end

    test "returns sort options for specified sort" do
      @query.sort = %w[updated desc]
      expected = [
        { "updated_at" => { "order" => "desc", "unmapped_type" => "date" } },
        "_score",
      ]
      assert_equal(expected, @query.build_sort)
    end

    test "accepts multiple sort fields" do
      @query.sort = %w[created asc updated desc]
      expected = [
        { "created_at" => { "order" => "asc", "unmapped_type" => "date" } },
        { "updated_at" => { "order" => "desc", "unmapped_type" => "date" } },
        "_score",
      ]
      assert_equal(expected, @query.build_sort)
    end
  end

  test "does not escape colon-style emoji" do
    # This FF is irrelavent for this test
    GitHub.flipper[:labels_es_query_trigram].disable
    @query.phrase = ":rainbow:"
    expected = {
      bool: {
        must: {
          bool: {
            should: [
              {
                match: {
                  name: { query: ":rainbow:", boost: 1.5 },
                },
              },
              { match: { "name.ngram" => ":rainbow:" } },
              { match: { description: ":rainbow:" } },
            ],
          },
        },
        filter: { bool: { must: { term: { repo_id: @repo.id } } } },
      },
    }

    assert_equal expected, @query.build_query
  end

  test "filters by repository when repo_id is given" do
    # This FF is irrelavent for this test
    GitHub.flipper[:labels_es_query_trigram].disable
    @query.phrase = "search"
    expected = {
      bool: {
        must: {
          bool: {
            should: [
              {
                match: {
                  name: { query: "search", boost: 1.5 },
                },
              },
              { match: { "name.ngram" => "search" } },
              { match: { description: "search" } },
            ],
          },
        },
        filter: { bool: { must: { term: { repo_id: @repo.id } } } },
      },
    }

    assert_equal expected, @query.build_query
  end

  test "prunes results that no longer exist" do
    label = create(:label, repository: @repo)
    make_searchable(label)

    # Make sure callbacks don't try to remove the label from the search index
    assert_enqueued_jobs 0, only: RemoveFromSearchIndexJob do
      Label.where(id: label.id).delete_all
    end

    search_query = Search::Queries::LabelQuery.new(phrase: label.name, current_user: @user, repo_id: label.repository_id)
    assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["label", label.id.to_s, label.repository_id.to_s]) do
      search_query.execute
    end
  end

  test "search multiple words with OR semantic" do
    label_bug = create(:label, name: "bug", repository: @repo)
    label_feature = create(:label, name: "feature", repository: @repo)
    make_searchable(label_bug, label_feature)

    search_query = Search::Queries::LabelQuery.new(phrase: "bug feature", current_user: @user, repo_id: @repo.id)
    results = search_query.execute

    assert_equal 2, results.count
  end

  test "correctly sort results when search starts mid-word, with labels_es_query_trigram enaled" do
    GitHub.flipper[:labels_es_query_trigram].enable
    name_description = [
      { name: "exploration", description: "" },
      { name: "extensions", description: "Issues concerning extensions" },
      { name: "extension-development", description: "Issues for developing extensions" },
      { name: "extensions-recommendations", description: "Extension recommendations issues" },
      { name: "extension-activation", description: "Issues related to extension activation" },
      { name: "extension-signature", description: "Issues related to extension signature verification" },
      { name: "extension-editor", description: "" },
      { name: "extension-host", description: "Extension host issues" },
      { name: "extension-prerelease", description: "Issues related extension prerelease support" },
      { name: "file-explorer", description: "Explorer widget issues" },
      { name: "remote-explorer", description: "Remote explorer view" }
    ]

    labels = []
    name_description.each do |label|
      labels.push create(:label, name: label[:name], description: label[:description], repository: @repo)
    end

    make_searchable(*labels)

    search_query = Search::Queries::LabelQuery.new(phrase: "explo", current_user: @user, repo_id: @repo.id)

    results = search_query.execute

    assert_equal 10, results.count

    result_names = results.map { |result| result["_source"]["name"] }
    assert_equal %w[exploration file-explorer remote-explorer extensions extension-development extensions-recommendations
      extension-activation extension-signature extension-editor extension-host], result_names
  end

  test "mid-name term search keeps being boken with FF disabled" do
    GitHub.flipper[:labels_es_query_trigram].disable
    name_description = [
      { name: "exploration", description: "" },
      { name: "extensions", description: "Issues concerning extensions" },
      { name: "extension-development", description: "Issues for developing extensions" },
      { name: "extensions-recommendations", description: "Extension recommendations issues" },
      { name: "extension-activation", description: "Issues related to extension activation" },
      { name: "extension-signature", description: "Issues related to extension signature verification" },
      { name: "extension-editor", description: "" },
      { name: "extension-host", description: "Extension host issues" },
      { name: "extension-prerelease", description: "Issues related extension prerelease support" },
      { name: "file-explorer", description: "Explorer widget issues" },
      { name: "remote-explorer", description: "Remote explorer view" }
    ]

    labels = []
    name_description.each do |label|
      labels.push create(:label, name: label[:name], description: label[:description], repository: @repo)
    end

    make_searchable(*labels)

    search_query = Search::Queries::LabelQuery.new(phrase: "explo", current_user: @user, repo_id: @repo.id)

    results = search_query.execute

    assert_equal 9, results.count

    result_names = results.map { |result| result["_source"]["name"] }
    assert_equal %w[exploration extensions extension-development extensions-recommendations
      extension-activation extension-signature extension-editor extension-host extension-prerelease], result_names
  end

  test "Searches over native emojis" do
    label_name = "#{GRIN_EMOJI} Comp"

    make_searchable(create(:label, name: label_name, repository: @repo))

    query_strings = [
      label_name,
      "#{GRIN_EMOJI}",
      "#{GRIN_EMOJI} Comp",
    ]

    query_strings.each do |query_string|
      search_query = Search::Queries::LabelQuery.new(phrase: query_string, current_user: @user, repo_id: @repo.id)
      results = search_query.execute
      assert results.count > 0
      result_label_names = results.map { |r| r["_model"].name }
      assert_includes result_label_names, label_name, "Expected to find label with name: `#{GRIN_EMOJI} Computers`"
    end
  end

  test "search by phrase with reserved characters" do
    reset_search
    with_es_refresh do
      label_names = [":rainbow: onboarding", ":rainbow:", "test:github/branch_bug", "rest(github)", "test[github^test]",
                      "branch_bug", "github&microsoft", "github|label", "github!repo", "ghh~branch", "gth*branch",
                      "github:branch", "gh\"branch\""]

      label_names.each do |name|
        make_searchable(create(:label, name: name, repository: @repo))
      end

      label_names.each do |name|
        search_query = Search::Queries::LabelQuery.new(phrase: name, current_user: @user, repo_id: @repo.id)
        results = search_query.execute
        result_label_names = results.map { |r| r["_model"].name }
        assert results.count > 0
        assert_includes result_label_names, name, "Expected to find label with name: #{name}"
      end
    end
  end
end
