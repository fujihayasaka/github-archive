# typed: false
# frozen_string_literal: true

require "test_helper"

class AchievableSubstitutedTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @user = create(:verified_user)

    @ach0 = create(:achievement, :heart_on_your_sleeve, user: @user, tier: 0)
    @ach1 = create(:achievement, :heart_on_your_sleeve, user: @user, tier: 1)
  end

  def refute_association_loads_during(&block)
    callback = ->(association) do
      reflection = association.reflection
      raise "Refusing to load association #{reflection.name} from #{reflection.active_record.name}"
    end

    GitHub::AssociationInstrumenter.track_loads(callback, &block)
  end

  def subs(text, achievement: @ach0, current_user: @user, visible_models: [], view_context: nil)
    kwargs = {
      achievement: achievement.reload,
      current_user: current_user,
      visible_models: visible_models,
    }
    kwargs[:view_context] = view_context if view_context
    result = refute_association_loads_during do
      Achievable::SubstitutedText.new(text, **kwargs).async_render
    end
    result.sync
  end

  def create_commit(ref, user, *coauthors)
    message = "Commit message".dup
    message << "\n\n" if coauthors.any?
    coauthors.each do |coauthor|
      name = coauthor.try(:name) || coauthor[:name]
      email = coauthor.try(:email) || coauthor[:email]
      message << "Co-authored-by: #{name} <#{email}>\n"
    end

    ref.append_commit({
      message: message,
      committer: { name: user.name, email: user.email },
      author: user,
    }, user)
  end

  def create_pr(authors)
    repo = create(:repository, owner: @user, from_example: :simple)
    ref = repo.heads.create("branch", repo.heads.find("master").target, authors.first)
    create_commit(ref, authors.first, *authors.drop(1))
    make_pr(repo, repo, branch: "branch")
  end

  context ".needs_unlocking_model?" do
    test "returns false for text with no substitutions" do
      refute Achievable::SubstitutedText.needs_unlocking_model?("no patterns here")
    end

    test "returns false for text with substitutions that do not use the unlocking model" do
      refute Achievable::SubstitutedText.needs_unlocking_model?("the %{threshold} pattern does not")
    end

    test "returns true for text with subtitutions that do use the unlocking model" do
      assert Achievable::SubstitutedText.needs_unlocking_model?("the %{reaction_count_phrase} pattern does")
    end
  end

  context "threshold" do
    test "interpolates the tier threshold" do
      assert_equal "before 2 after", subs("before %{threshold} after", achievement: @ach0)
      assert_equal "before 16 after", subs("before %{threshold} after", achievement: @ach1)
    end
  end

  context "threshold_ordinal" do
    test "interpolates the tier threshold as an ordinal number" do
      assert_equal "aaa 2nd zzz", subs("aaa %{threshold_ordinal} zzz", achievement: @ach0)
      assert_equal "aaa 16th zzz", subs("aaa %{threshold_ordinal} zzz", achievement: @ach1)
    end
  end

  context "threshold_duration" do
    test "interpolates the tier threshold as a time duration" do
      qd = create(:achievement, :quickdraw)
      assert_equal "[[ 5 minutes ]]", subs("[[ %{threshold_duration} ]]", achievement: qd)
    end
  end

  context "link" do
    test "interpolates ACV link text" do
      acv = create(:achievement, :arctic_code_vault_contributor)
      assert_equal "2020 GitHub Archive Program", subs("%{link}", achievement: acv)
    end

    test "interpolates Mars link text" do
      mars = create(:achievement, :mars_2020_contributor)
      assert_equal "Mars 2020 Helicopter Mission", subs("%{link}", achievement: mars)
    end

    test "uses the link_to helper from the view context" do
      context = Achievable::SubstitutedText::StringContext.new
      context.expects(:link_to).with(
        Achievable::ArcticCodeVaultContributor::LINK_TEXT,
        Achievable::ArcticCodeVaultContributor::LINK_HREF,
      ).returns("<result>")

      acv = create(:achievement, :arctic_code_vault_contributor)

      assert_equal "<result>", subs("%{link}", achievement: acv, view_context: context)
    end
  end

  context "achieving_user_login" do
    test "uses the user's login with an @" do
      assert_equal "@#{@ach0.user.login}", subs("%{achieving_user_login}", achievement: @ach0)
    end

    test "uses a placeholder for deleted users" do
      @user.delete
      assert_equal "(deleted user)", subs("%{achieving_user_login}", achievement: @ach0)
    end
  end

  context "achieving_user_name" do
    test "uses the user's profile name if one is present" do
      create(:profile, user: @user, name: "Rando Calrissian")
      assert_equal "Rando Calrissian", subs("%{achieving_user_name}", achievement: @ach0)
    end

    test "uses the user's login if no profile name is set" do
      assert_equal @user.login, subs("%{achieving_user_name}", achievement: @ach0)
    end

    test "uses a placeholder for deleted users" do
      @user.delete
      assert_equal "(deleted user)", subs("%{achieving_user_name}", achievement: @ach0)
    end
  end

  context "reaction_count_phrase" do
    test "uses a pluralized count of reactions to an unlocking issue" do
      issue = create(:issue)
      create_list(:issue_reaction, 5, issue: issue)
      @ach0.update!(unlocking_model: issue)

      assert_equal "5 reactions", subs("%{reaction_count_phrase}", achievement: @ach0, visible_models: [issue])
    end

    test "uses a pluralized count of reactions to an unlocking pull request" do
      pr = create(:pull_request, :disable_disk_access)
      create(:issue_reaction, issue: pr.issue)
      @ach0.update!(unlocking_model: pr)

      assert_equal "1 reaction", subs("%{reaction_count_phrase}", achievement: @ach0, visible_models: [pr])
    end

    test "falls back to a generic phrase for a non-visible issue" do
      issue = create(:issue)
      create_list(:issue_reaction, 2, issue: issue)
      @ach0.update!(unlocking_model: issue)

      assert_equal "many reactions", subs("%{reaction_count_phrase}", achievement: @ach0, visible_models: [])
    end
  end

  context "coauthor_login_mention" do
    test "uses a comma-delimited sentence of user mentions" do
      coauthor0, coauthor1, coauthor2 = create_list(:user, 3)

      pr = create_pr([coauthor0, coauthor1, coauthor2])
      @ach0.update!(unlocking_model: pr)

      assert_equal "@#{coauthor0}, @#{coauthor1}, and @#{coauthor2}", subs("%{coauthor_login_mention}",
        achievement: @ach0, visible_models: [pr])
    end

    test "uses a single user mention" do
      coauthor = create(:user)

      pr = create_pr([@user, coauthor])
      @ach0.update!(unlocking_model: pr)

      assert_equal "@#{coauthor}", subs("%{coauthor_login_mention}", achievement: @ach0, visible_models: [pr])
    end

    test "uses a placeholder with no present users" do
      coauthor = create(:user)

      pr = create_pr([@user, coauthor])
      @ach0.update!(unlocking_model: pr)

      coauthor.delete

      assert_equal "an unknown user", subs("%{coauthor_login_mention}", achievement: @ach0, visible_models: [pr])
    end

    test "uses a placeholder for a non-visible pr" do
      coauthor = create(:user)

      pr = create_pr([@user, coauthor])
      @ach0.update!(unlocking_model: pr)

      assert_equal "an unknown user", subs("%{coauthor_login_mention}", achievement: @ach0, visible_models: [])
    end
  end

  context "repository_with_pronoun" do
    test "uses singular past-tense with a single repository in the list" do
      create(:user_metadata, user: @user, has_acv_badge: true)
      repo = create(:acv_contributor, contributor_email: @user.emails.take!).repository
      ach = create(:achievement, :arctic_code_vault_contributor, user: @user)

      assert_equal "this repository was",
        subs("%{repository_with_pronoun}", achievement: ach, visible_models: [repo])
    end

    test "uses plural past-tense with multiple repositories less than the limit" do
      create(:user_metadata, user: @user, has_acv_badge: true)
      repos = create_list(:acv_contributor, 2, contributor_email: @user.emails.take!).map(&:repository)
      ach = create(:achievement, :arctic_code_vault_contributor, user: @user)

      assert_equal "these repositories were",
        subs("%{repository_with_pronoun}", achievement: ach, visible_models: repos)
    end

    test "uses plural past-tense with more repositories than the limit" do
      create(:user_metadata, user: @user, has_acv_badge: true)
      repos = create_list(:acv_contributor, 4, contributor_email: @user.emails.take!).map(&:repository)
      ach = create(:achievement, :arctic_code_vault_contributor, user: @user)

      assert_equal "these repositories, and more, were",
        subs("%{repository_with_pronoun}", achievement: ach, visible_models: repos)
    end
  end

  context "acv_count_with_repository" do
    test "uses 'several' for more than three repositories" do
      email = @user.emails.take!
      create_list(:acv_contributor, 4, contributor_email: email)
      ach = create(:achievement, :arctic_code_vault_contributor, user: @user)

      assert_equal "to several repositories", subs("%{acv_count_with_repository}", achievement: ach)
    end

    test "lists the count for less than three repositories" do
      email = @user.emails.take!
      create_list(:acv_contributor, 2, contributor_email: email)
      ach = create(:achievement, :arctic_code_vault_contributor, user: @user)

      assert_equal "to 2 repositories", subs("%{acv_count_with_repository}", achievement: ach)
    end

    test "falls back to 'unknown' repositories" do
      ach = create(:achievement, :arctic_code_vault_contributor, user: @user)
      @user.delete

      assert_equal "to unknown repositories", subs("%{acv_count_with_repository}", achievement: ach)
    end
  end

  context "nasa_2020_count_with_repository" do
    test "uses 'several' for more than three repositories" do
      nasa_highlight = create(
        :profile_highlight,
        user: @user,
        highlight_type: :nasa_2020,
        hidden: false,
        eligible: true,
      )
      email = @user.emails.take!
      create_list(:profile_highlight_contribution, 4, profile_highlight: nasa_highlight, contributor_email: email)
      ach = create(:achievement, :mars_2020_contributor, user: @user)

      assert_equal "to several repositories", subs("%{nasa_2020_count_with_repository}", achievement: ach)
    end

    test "lists the count for less than three repositories" do
      nasa_highlight = create(
        :profile_highlight,
        user: @user,
        highlight_type: :nasa_2020,
        hidden: false,
        eligible: true,
      )
      email = @user.emails.take!
      create(:profile_highlight_contribution, profile_highlight: nasa_highlight, contributor_email: email)
      ach = create(:achievement, :mars_2020_contributor, user: @user)

      assert_equal "to 1 repository", subs("%{nasa_2020_count_with_repository}", achievement: ach)
    end

    test "falls back to 'unknown' repositories" do
      ach = create(:achievement, :mars_2020_contributor, user: @user)

      assert_equal "to unknown repositories", subs("%{nasa_2020_count_with_repository}", achievement: ach)
    end
  end

  context "public_sponsors_sum_and_types" do
    test "reports pluralized sponsorship count" do
      sponsor = create(
        :credit_card_user,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
      create_list(:sponsorship, 4, sponsor: sponsor)
      create(:sponsorship, :private, sponsor: sponsor)
      create(:sponsorship, :inactive, sponsor: sponsor)
      @ach0.update!(user: sponsor)

      assert_equal "is sponsoring 4 organizations or users", subs("%{public_sponsors_sum_and_types}")
    end

    test "reports pluralized inactive sponsorship count test" do
      sponsor = create(
        :credit_card_user,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
      create(:sponsorship, :private, sponsor: sponsor)
      create_list(:sponsorship, 5, :inactive, sponsor: sponsor)
      @ach0.update!(user: sponsor)

      assert_equal "has sponsored 5 organizations or users", subs("%{public_sponsors_sum_and_types}")
    end

    test "reports singular inactive sponsorship count test" do
      sponsor = create(
        :credit_card_user,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
      create(:sponsorship, :private, sponsor: sponsor)
      create_list(:sponsorship, 1, :inactive, sponsor: sponsor)
      @ach0.update!(user: sponsor)

      assert_equal "has sponsored 1 organization or user", subs("%{public_sponsors_sum_and_types}")
    end

    test "falls back to a generic phrase" do
      @user.delete

      assert_equal "is sponsoring users and/or organizations on GitHub", subs("%{public_sponsors_sum_and_types}")
    end
  end
end
