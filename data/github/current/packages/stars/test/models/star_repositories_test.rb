# typed: true
# frozen_string_literal: true

require "test_helper"

class StarRepositoriesTest < GitHub::TestCase
  fixtures do
    create :language_name, name: "JavaScript", linguist_id: 183
    coffeescript = create :language_name, name: "CoffeeScript", linguist_id: 63
    @ruby = create :language_name, name: "Ruby", linguist_id: 326
    elisp = create :language_name, name: "Emacs Lisp", linguist_id: 102

    @rails = create(:repository, name: "rails", primary_language_name_id: @ruby.id)
    @sinatra = create(:repository, name: "sinatra", primary_language_name_id: @ruby.id)
    @emacs = create(:repository, name: "Emacs", primary_language_name_id: elisp.id)
    @python = create(:repository, name: "Python", primary_language_name_id: nil)
    create(:repository, name: "turbolinks", primary_language_name_id: coffeescript.id)
    @user = create(:user)

    @org  = create :organization, plan: "gold"
    @team = create(:team, organization: @org)
    @team.add_member @user

    @user.star(@rails)
    @user.star(@sinatra)
  end

  test "#starred_public_repositories_by_language returns the right counts" do
    assert_equal({ "Ruby" => 2 }, @user.starred_public_repositories_by_language)
    @user.star(@emacs)
    assert_equal({ "Ruby" => 2, "Emacs Lisp" => 1 }, @user.starred_public_repositories_by_language)
  end

  test "#starred_public_repositories_by_language doesn't include repos without a primary language" do
    assert_equal({ "Ruby" => 2 }, @user.starred_public_repositories_by_language)
    @user.star(@python)
    assert_equal({ "Ruby" => 2 }, @user.starred_public_repositories_by_language)
  end

  test "#starred_public_repositories_by_language dont show private repos" do
    secret_repo = create(:private_repository, name: "secret_repo", primary_language_name_id: @ruby.id, owner: @org)
    @user.star(secret_repo)
    assert_equal({ "Ruby" => 2 }, @user.starred_public_repositories_by_language)
  end

  test "#starred_repositories_by_language should show private repos" do
    secret_repo = create(:private_repository, name: "secret_repo", primary_language_name_id: @ruby.id, owner: @org)
    @user.star(secret_repo)
    assert_equal({ "Ruby" => 3 }, @user.starred_repositories_by_language)
  end
end
