# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueImportsTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @user = @repo.owner
    @issue = create :issue, user: @user, repository: @repo
    @issue2 = create :issue, user: @user, repository: @repo
  end

  test "creates import" do
    import = IssueImport.new repository: @repo, importer: @user
    import.importing @issue
    import.save!

    assert_equal import, saved_import = IssueImport.find(T.must(import.id))
    assert_equal @repo, saved_import.repository
    assert_equal @user, saved_import.importer
    assert saved_import.imported?(@issue)
    assert !saved_import.imported?(@issue2)
  end
end
