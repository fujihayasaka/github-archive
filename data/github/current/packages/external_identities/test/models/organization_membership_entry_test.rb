# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/ability_models"

module OrganizationMembershipEntrySharedMethods
  def setup_test
    # we need the adder_type parameter if we are doing an :enterprise_team enabled version
    if EnterpriseTeam.enabled_for_organizations?(business: @business)
      #organization_mixed_user
      OrganizationMembershipEntry.create_entry(user: @organization_mixed_user, organization_id: @organization.id, adder_id: 1, ability_id: 1, derived: true, adder_type: :external_team)
      OrganizationMembershipEntry.create_entry(user: @organization_mixed_user, organization_id: @organization.id, adder_id: 2, ability_id: 1, derived: true, adder_type: :external_team)
      OrganizationMembershipEntry.create_entry(
        user: @organization_mixed_user,
        organization_id: @organization.id,
        adder_id: @organization.admin.id,
        ability_id: 1,
        derived: false,
        adder_type: :admin
      )

      #organization_explicit_user
      OrganizationMembershipEntry.create_entry(
        user: @organization_explicit_user,
        organization_id: @organization.id,
        adder_id: @organization.admin.id,
        ability_id: 1,
        derived: false,
        adder_type: :admin
      )

      #organization_derived_user
      OrganizationMembershipEntry.create_entry(user: @organization_derived_user, organization_id: @organization.id, adder_id: 1, ability_id: 1, derived: true, adder_type: :external_team)
      OrganizationMembershipEntry.create_entry(user: @organization_derived_user, organization_id: @organization.id, adder_id: 2, ability_id: 1, derived: true, adder_type: :external_team)
    else
      #organization_mixed_user
      OrganizationMembershipEntry.create_entry(user: @organization_mixed_user, organization_id: @organization.id, adder_id: 1, ability_id: 1, derived: true)
      OrganizationMembershipEntry.create_entry(user: @organization_mixed_user, organization_id: @organization.id, adder_id: 2, ability_id: 1, derived: true)
      OrganizationMembershipEntry.create_entry(
        user: @organization_mixed_user,
        organization_id: @organization.id,
        adder_id: @organization.admin.id,
        ability_id: 1,
        derived: false
      )

      #organization_explicit_user
      OrganizationMembershipEntry.create_entry(
        user: @organization_explicit_user,
        organization_id: @organization.id,
        adder_id: @organization.admin.id,
        ability_id: 1,
        derived: false
      )

      #organization_derived_user
      OrganizationMembershipEntry.create_entry(user: @organization_derived_user, organization_id: @organization.id, adder_id: 1, ability_id: 1, derived: true)
      OrganizationMembershipEntry.create_entry(user: @organization_derived_user, organization_id: @organization.id, adder_id: 2, ability_id: 1, derived: true)
    end
  end
end

module OrganizationMembershipEntryValidationSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_all_parameters_are_required_to_create_an_organization_membership_entry
    org_membership_entry = OrganizationMembershipEntry.create(
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      adder_type: :admin,
      ability_id: 1
    )
    refute_predicate org_membership_entry, :valid?

    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      adder_id: @organization.admin.id,
      adder_type: :admin,
      ability_id: 1
    )
    refute_predicate org_membership_entry, :valid?

    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      organization_id: @organization.id,
      adder_type: :admin,
      ability_id: 1
    )
    refute_predicate org_membership_entry, :valid?

    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1
    )
    refute_predicate org_membership_entry, :valid?

    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      adder_type: :admin
    )
    refute_predicate org_membership_entry, :valid?

    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      adder_type: :admin,
      ability_id: 1
    )
    assert_predicate org_membership_entry, :valid?
  end

  def test_team_is_accepted_value_for_adder_type_to_create_an_organization_membership_entry
    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      adder_type: :external_team,
      ability_id: 1
    )
    assert_predicate org_membership_entry, :valid?
  end

  def test_user_is_accepted_value_for_adder_type_to_create_an_organization_membership_entry
    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      adder_type: :admin,
      ability_id: 1
    )
    assert_predicate org_membership_entry, :valid?
  end

  def test_unaccepted_value_for_adder_type_to_create_an_organization_membership_entry
    assert_raises ArgumentError do
      org_membership_entry = OrganizationMembershipEntry.create(
        user_id: @user.id,
        organization_id: @organization.id,
        adder_id: @organization.admin.id,
        adder_type: :organization,
        ability_id: 1
      )
    end
  end

  def test_enterprise_team_is_accepted_value_for_adder_type_to_create_an_organization_membership_entry
    team_id = 1
    org_membership_entry = OrganizationMembershipEntry.create(
      user_id: @user.id,
      organization_id: @organization.id,
      adder_id: team_id,
      adder_type: :enterprise_team,
      ability_id: 1
    )
    assert_predicate org_membership_entry, :valid?
  end
end

module OrganizationMembershipEntryCreateDerivedMembershipEntrySharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_unable_to_create_a_derived_organization_membership_entry_for_anything_not_user
    #organization
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @organization,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: true
    )
    assert_nil org_membership_entry

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: integration.bot,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: true
    )
    assert_nil org_membership_entry
  end

  def test_adder_type_would_be_team_when_creating_derived_organization_membership_entry_for_a_user
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @user,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: true
    )

    assert_predicate org_membership_entry, :valid?
  end

  def test_all_method_arguments_are_required_to_create_derived_organization_membership_entry_for_a_user
    assert_raises ActiveRecord::RecordInvalid do
      org_membership_entry = OrganizationMembershipEntry.create_entry(
        user: @user,
        organization_id: nil,
        adder_id: @organization.admin.id,
        ability_id: 1,
        derived: true
      )
    end

    assert_raises ActiveRecord::RecordInvalid do
      org_membership_entry = OrganizationMembershipEntry.create_entry(
        user: @user,
        organization_id: @organization.id,
        adder_id: nil,
        ability_id: 1,
        derived: true
      )
    end

    assert_raises ActiveRecord::RecordInvalid do
      org_membership_entry = OrganizationMembershipEntry.create_entry(
        user: @user,
        organization_id: @organization.id,
        adder_id: @organization.admin.id,
        ability_id: nil,
        derived: true
      )
    end

    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @user,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: true
    )

    assert_predicate org_membership_entry, :valid?
    assert_equal @organization.admin.id, org_membership_entry.adder_id
    assert_equal @organization.id, org_membership_entry.organization_id
    assert_equal 1, org_membership_entry.ability_id
  end
end

module OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntrySharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_unable_to_create_a_organization_membership_entry_for_anything_not_user_with_enterprise_team
    #organization
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @organization,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: true,
      adder_type: :enterprise_team
    )
    assert_nil org_membership_entry

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: integration.bot,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: true,
      adder_type: :enterprise_team
    )
    assert_nil org_membership_entry
  end

  def test_adder_type_would_be_enterprise_team_when_creating_organization_membership_entry_for_a_user
    OrganizationMembershipEntry.stubs(:enterprise_team_enabled?).returns(true)

    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @user,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: true,
      adder_type: :enterprise_team
    )

    assert_predicate org_membership_entry, :valid?
    assert_equal :enterprise_team, org_membership_entry.adder_type.to_sym
  end
end

module OrganizationMembershipEntryCreateExplicitMembershipEntrySharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_unable_to_create_a_explicit_organization_membership_entry_for_anything_not_user
    #organization
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @organization,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: false
    )
    assert_nil org_membership_entry

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: integration.bot,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: false
    )
    assert_nil org_membership_entry
  end

  def test_adder_type_would_be_user_when_creating_explicit_organization_membership_entry_for_a_user
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @user,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: false
    )

    assert_predicate org_membership_entry, :valid?
  end

  def test_all_method_arguments_are_required_to_create_explicit_organization_membership_entry_for_a_user
    assert_raises ActiveRecord::RecordInvalid do
      org_membership_entry = OrganizationMembershipEntry.create_entry(
        user: @user,
        organization_id: nil,
        adder_id: @organization.admin.id,
        ability_id: 1,
        derived: false
      )
    end

    assert_raises ActiveRecord::RecordInvalid do
      org_membership_entry = OrganizationMembershipEntry.create_entry(
        user: @user,
        organization_id: @organization.id,
        adder_id: nil,
        ability_id: 1,
        derived: false
      )
    end

    assert_raises ActiveRecord::RecordInvalid do
      org_membership_entry = OrganizationMembershipEntry.create_entry(
        user: @user,
        organization_id: @organization.id,
        adder_id: @organization.admin.id,
        ability_id: nil,
        derived: false
      )
    end

    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @user,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: false
    )

    assert_predicate org_membership_entry, :valid?
    assert_equal @organization.admin.id, org_membership_entry.adder_id
    assert_equal @organization.id, org_membership_entry.organization_id
    assert_equal 1, org_membership_entry.ability_id
  end

  def test_unable_to_create_a_explicit_organization_membership_entry_for_a_user_if_there_is_a_preexisting_explicit_membership
    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @user,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      ability_id: 1,
      derived: false
    )
    assert_predicate org_membership_entry, :valid?

    org_membership_entry = OrganizationMembershipEntry.create_entry(
      user: @user,
      organization_id: @organization.id,
      adder_id: @business.owners.first.id,
      ability_id: 1,
      derived: false
    )
    assert_nil org_membership_entry
  end
end

module OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntryBulkSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_organization_membership_entries_are_created_when_using_create_entry_bulk_with_enterprise_team
    OrganizationMembershipEntry.stubs(:enterprise_team_enabled?).returns(true)

    team = create :team

    subject = ASubject.create
    actor1 = AnActor.create
    actor2 = AnActor.create
    ability1 = subject.grant actor1, :read
    ability2 = subject.grant actor2, :read

    abilities = [ability1, ability2]

    assert_equal 0, OrganizationMembershipEntry.where(ability_id: abilities.map(&:id)).count

    OrganizationMembershipEntry.bulk_create_entry(
      abilities: abilities,
      organization_id: @organization.id,
      adder_id: team.id,
      derived: true,
      adder_type: :enterprise_team
    )

    assert_equal 2, OrganizationMembershipEntry.where(ability_id: abilities.map(&:id)).count
    created_entries = OrganizationMembershipEntry.where(ability_id: abilities.map(&:id))
    created_entries.each do |entry|
      assert_equal :enterprise_team, entry.adder_type.to_sym
    end
  end
end

module OrganizationMembershipEntryCreateDerivedMembershipEntryBulkSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_adder_type_would_be_team_when_creating_derived_organization_membership_entry_bulk
    user1 = create @user_factory, business: @business
    user2 = create @user_factory, business: @business
    user_ids = [user1.id, user2.id]

    assert_equal 0, OrganizationMembershipEntry.where(user_id: user_ids, organization_id: @organization.id, adder_type: :admin).count

    @organization.add_member(user1)
    @organization.add_member(user2)

    assert_equal 2, OrganizationMembershipEntry.where(user_id: user_ids, organization_id: @organization.id, adder_type: :admin).count

    # the ability ids don't actually matter as long as we don't depend on them for the test
    # what matters is the users the abilities are attached to
    # ex: the entries in setup_test all use ability id 1
    ability1 = user1.get_organization_ability(@organization.id)
    ability2 = user2.get_organization_ability(@organization.id)
    abilities = [ability1, ability2]

    org_membership_entry = OrganizationMembershipEntry.bulk_create_entry(
      abilities: abilities,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      derived: true
    )

    assert_equal 2, OrganizationMembershipEntry.where(user_id: user_ids, organization_id: @organization.id, adder_type: :external_team).count
  end
end

module OrganizationMembershipEntryCreateExplicitMembershipEntryBulkSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }


  def test_unable_to_create_a_explicit_organization_membership_entry_for_a_user_if_there_is_a_preexisting_explicit_membership
    user1 = create @user_factory, business: @business
    user2 = create @user_factory, business: @business
    user_ids = [user1.id, user2.id]

    assert_equal 0, OrganizationMembershipEntry.where(user_id: user_ids, organization_id: @organization.id, adder_type: :admin).count

    @organization.add_member(user1)
    @organization.add_member(user2)

    assert_equal 2, OrganizationMembershipEntry.where(user_id: user_ids, organization_id: @organization.id, adder_type: :admin).count

    # the ability ids don't actually matter as long as we don't depend on them for the test
    # what matters is the users the abilities are attached to
    # ex: the entries in setup_test all use ability id 1
    ability1 = user1.get_organization_ability(@organization.id)
    ability2 = user2.get_organization_ability(@organization.id)
    abilities = [ability1, ability2]

    org_membership_entry = OrganizationMembershipEntry.bulk_create_entry(
      abilities: abilities,
      organization_id: @organization.id,
      adder_id: @organization.admin.id,
      derived: false
    )

    assert_equal 2, OrganizationMembershipEntry.where(user_id: user_ids, organization_id: @organization.id, adder_type: :admin).count
  end
end

module OrganizationMembershipEntryRemoveDerivedMembershipEntrySharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_unable_to_remove_a_derived_organization_membership_entry_for_anything_not_user
    #organization
    assert_no_difference ["OrganizationMembershipEntry.count"] do
      org_membership_entry = OrganizationMembershipEntry.remove_entry(
        user: @organization,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_id: 1
      )
      assert_nil org_membership_entry
    end

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    assert_no_difference ["OrganizationMembershipEntry.count"] do
      org_membership_entry = OrganizationMembershipEntry.remove_entry(
        user: integration.bot,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_id: 1
      )

      assert_nil org_membership_entry
    end
  end

  def test_unable_to_remove_a_derived_membership_without_passing_in_adder_id
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 3, user_org_membership_entries.count

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      org_membership_entry = OrganizationMembershipEntry.remove_entry(
        user: @organization_mixed_user,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true
      )
      assert_nil org_membership_entry
    end
  end

  def test_unable_to_remove_a_derived_membership_without_passing_in_adder_id_ff_enabled
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 3, user_org_membership_entries.count

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      org_membership_entry = OrganizationMembershipEntry.remove_entry(
        user: @organization_mixed_user,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_type: :external_team
      )
      assert_nil org_membership_entry
    end
  end

  def test_no_change_to_organization_membership_entry_reference_count_if_user_does_not_have_derived_membership
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_explicit_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      OrganizationMembershipEntry.remove_entry(
        user: @organization_explicit_user,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_id: 1
      )
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_explicit_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count
  end

  def test_no_change_to_organization_membership_entry_reference_count_if_user_does_not_have_derived_membership_ff_enabled
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_explicit_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      OrganizationMembershipEntry.remove_entry(
        user: @organization_explicit_user,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_id: 1,
        adder_type: :external_team
      )
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_explicit_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count
  end

  def test_change_to_organization_membership_entry_reference_count_when_removing_derived_user_organization_membership_entry
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 3, user_org_membership_entries.count

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      assert_query_count_per_table({ organization_membership_entries: 1 }) do
        OrganizationMembershipEntry.remove_entry(
          user: @organization_mixed_user,
          organization_id: @organization.id,
          ability_id: 1,
          derived: true,
          adder_id: 1
        )
      end
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 2, user_org_membership_entries.count

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      assert_query_count_per_table({ organization_membership_entries: 1 }) do
        OrganizationMembershipEntry.remove_entry(
          user: @organization_mixed_user,
          organization_id: @organization.id,
          ability_id: 1,
          derived: true,
          adder_id: 2
        )
      end
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count
    refute OrganizationMembershipEntry.derived?(user: @organization_mixed_user, organization_id: @organization.id, ability_id: 1)
  end

  def test_change_to_organization_membership_entry_reference_count_when_removing_derived_user_organization_membership_entry_ff_enabled
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 3, user_org_membership_entries.count

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      assert_query_count_per_table({ organization_membership_entries: 1 }) do
        OrganizationMembershipEntry.remove_entry(
          user: @organization_mixed_user,
          organization_id: @organization.id,
          ability_id: 1,
          derived: true,
          adder_id: 1,
          adder_type: :external_team
        )
      end
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 2, user_org_membership_entries.count

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      assert_query_count_per_table({ organization_membership_entries: 1 }) do
        OrganizationMembershipEntry.remove_entry(
          user: @organization_mixed_user,
          organization_id: @organization.id,
          ability_id: 1,
          derived: true,
          adder_id: 2,
          adder_type: :external_team
        )
      end
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count
    refute OrganizationMembershipEntry.derived?(user: @organization_mixed_user, organization_id: @organization.id, ability_id: 1)
  end
end

module OrganizationMembershipEntryRemoveExplicitMembershipEntrySharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_unable_to_remove_a_explicit_organization_membership_entry_for_anything_not_user
    #organization
    org_membership_entry = OrganizationMembershipEntry.remove_entry(
      user: @organization,
      organization_id: @organization.id,
      ability_id: 1,
      derived: false
    )
    assert_nil org_membership_entry

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    org_membership_entry = OrganizationMembershipEntry.remove_entry(
      user: integration.bot,
      organization_id: @organization.id,
      ability_id: 1,
      derived: false
    )
    assert_nil org_membership_entry
  end

  def test_no_change_to_organization_membership_entry_reference_count_if_user_does_not_have_explicit_membership
    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_derived_user.id, organization_id: @organization.id)
    assert_equal 2, user_org_membership_entries.count

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      OrganizationMembershipEntry.remove_entry(
        user: @organization_derived_user,
        organization_id: @organization.id,
        ability_id: 1,
        derived: false
      )
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_derived_user.id, organization_id: @organization.id)
    assert_equal 2, user_org_membership_entries.count
  end

  def test_change_to_organization_membership_entry_reference_count_when_removing_explicit_user_organization_membership_entry
    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 3, user_org_membership_entries.count

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      assert_query_count_per_table({ organization_membership_entries: 1 }) do
        OrganizationMembershipEntry.remove_entry(
          user: @organization_mixed_user,
          organization_id: @organization.id,
          ability_id: 1,
          derived: false
        )
      end
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 2, user_org_membership_entries.count
    refute OrganizationMembershipEntry.explicit?(user: @organization_mixed_user, organization_id: @organization.id, ability_id: 1)
  end
end

module OrganizationMembershipEntryRemoveEnterpriseTeamMembershipEntryEnterpriseTeamSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_unable_to_remove_a_organization_membership_entry_for_enterprise_team
    #organization
    assert_no_difference ["OrganizationMembershipEntry.count"] do
      org_membership_entry = OrganizationMembershipEntry.remove_entry(
        user: @organization,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_id: 1,
        adder_type: :enterprise_team
      )
      assert_nil org_membership_entry
    end

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    assert_no_difference ["OrganizationMembershipEntry.count"] do
      org_membership_entry = OrganizationMembershipEntry.remove_entry(
        user: integration.bot,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_id: 1,
        adder_type: :enterprise_team
      )

      assert_nil org_membership_entry
    end
  end

  def test_unable_to_remove_a_membership_without_passing_in_adder_id_for_enterprise_team
    OrganizationMembershipEntry.stubs(:enterprise_team_enabled?).returns(true)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_mixed_user.id, organization_id: @organization.id)
    assert_equal 3, user_org_membership_entries.count

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      org_membership_entry = OrganizationMembershipEntry.remove_entry(
        user: @organization_mixed_user,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_type: :enterprise_team
      )

      assert_nil org_membership_entry
    end
  end

  def test_no_change_to_organization_membership_entry_reference_count_if_user_does_not_have_membership_for_enterprise_team
    OrganizationMembershipEntry.stubs(:enterprise_team_enabled?).returns(true)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_explicit_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      OrganizationMembershipEntry.remove_entry(
        user: @organization_explicit_user,
        organization_id: @organization.id,
        ability_id: 1,
        derived: true,
        adder_id: 1,
        adder_type: :enterprise_team
      )
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: @organization_explicit_user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count
  end

  def test_change_to_organization_membership_entry_reference_count_when_removing_user_organization_membership_entry_for_enterprise_team
    user = create :user

    team = create :team, organization: @organization
    team_2 = create :team, organization: @organization

    OrganizationMembershipEntry.create_entry(user: user, organization_id: @organization.id, ability_id: 1, derived: true, adder_id: team.id, adder_type: :enterprise_team)
    OrganizationMembershipEntry.create_entry(user: user, organization_id: @organization.id, ability_id: 2, derived: true, adder_id: team_2.id, adder_type: :enterprise_team)

    #organization
    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: user.id, organization_id: @organization.id)
    assert_equal 2, user_org_membership_entries.count

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      assert_query_count_per_table({ organization_membership_entries: 1 }) do
        OrganizationMembershipEntry.remove_entry(
          user: user,
          organization_id: @organization.id,
          ability_id: 1,
          derived: true,
          adder_id: team.id,
          adder_type: :enterprise_team
        )
      end
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: user.id, organization_id: @organization.id)
    assert_equal 1, user_org_membership_entries.count

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      assert_query_count_per_table({ organization_membership_entries: 1 }) do
        OrganizationMembershipEntry.remove_entry(
          user: user,
          organization_id: @organization.id,
          ability_id: 2,
          derived: true,
          adder_id: team_2.id,
          adder_type: :enterprise_team
        )
      end
    end

    user_org_membership_entries = OrganizationMembershipEntry.where(user_id: user.id, organization_id: @organization.id)
    assert_equal 0, user_org_membership_entries.count
    refute OrganizationMembershipEntry.enterprise_team_managed?(user: user, organization_id: @organization.id, ability_id: 1)
  end
end

module OrganizationMembershipEntryExplicitSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_returns_false_for_anything_not_user
    #organization
    refute OrganizationMembershipEntry.explicit?(
      user: @organization,
      organization_id: @organization.id,
      ability_id: 1
    )

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    refute OrganizationMembershipEntry.explicit?(
      user: integration.bot,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returs_false_if_there_is_no_membership_entry_for_a_user
    refute OrganizationMembershipEntry.explicit?(
      user: @user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returs_true_if_there_is_explicit_membership_entry_for_a_user
    assert OrganizationMembershipEntry.explicit?(
      user: @organization_mixed_user,
      organization_id: @organization.id,
      ability_id: 1
    )

    assert OrganizationMembershipEntry.explicit?(
      user: @organization_explicit_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returs_false_if_there_is_no_explicit_membership_entry_for_a_user
    refute OrganizationMembershipEntry.explicit?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returs_false_if_the_explicit_membership_entry_for_a_user_is_removed
    assert OrganizationMembershipEntry.explicit?(
      user: @organization_explicit_user,
      organization_id: @organization.id,
      ability_id: 1
    )

    OrganizationMembershipEntry.remove_entry(
      user: @organization_explicit_user,
      organization_id: @organization.id,
      ability_id: 1,
      derived: false
    )

    refute OrganizationMembershipEntry.explicit?(
      user: @organization_explicit_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end
end

module OrganizationMembershipEntryDerivedSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_returns_false_for_anything_not_user
    #organization
    refute OrganizationMembershipEntry.derived?(
      user: @organization,
      organization_id: @organization.id,
      ability_id: 1
    )

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    refute OrganizationMembershipEntry.derived?(
      user: integration.bot,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returns_false_if_there_is_no_membership_entry_for_a_user
    refute OrganizationMembershipEntry.derived?(
      user: @user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returns_true_if_there_is_derived_membership_entry_for_a_user
    assert OrganizationMembershipEntry.derived?(
      user: @organization_mixed_user,
      organization_id: @organization.id,
      ability_id: 1
    )

    assert OrganizationMembershipEntry.derived?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returns_false_if_there_is_no_derived_membership_entry_for_a_user
    refute OrganizationMembershipEntry.derived?(
      user: @organization_explicit_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returns_false_if_the_derived_membership_entry_for_a_user_is_all_removed
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

    assert OrganizationMembershipEntry.derived?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )

    OrganizationMembershipEntry.remove_entry(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1,
      derived: true,
      adder_id: 1
    )

    assert OrganizationMembershipEntry.derived?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )


    OrganizationMembershipEntry.remove_entry(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1,
      derived: true,
      adder_id: 2
    )

    refute OrganizationMembershipEntry.derived?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returns_false_if_the_derived_membership_entry_for_a_user_is_all_removed_ff_enabled
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

    assert OrganizationMembershipEntry.derived?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )

    OrganizationMembershipEntry.remove_entry(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1,
      derived: true,
      adder_id: 1,
      adder_type: :external_team
    )

    assert OrganizationMembershipEntry.derived?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )


    OrganizationMembershipEntry.remove_entry(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1,
      derived: true,
      adder_id: 2,
      adder_type: :external_team
    )

    refute OrganizationMembershipEntry.derived?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end
end

module OrganizationMembershipEntryEnterpriseTeamSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_returns_false_for_anything_not_user_enterprise_team
    #organization
    refute OrganizationMembershipEntry.enterprise_team_managed?(
      user: @organization,
      organization_id: @organization.id,
      ability_id: 1
    )

    #bot
    integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    refute OrganizationMembershipEntry.enterprise_team_managed?(
      user: integration.bot,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returns_false_if_there_is_no_membership_entry_for_a_user_enterprise_team
    refute OrganizationMembershipEntry.enterprise_team_managed?(
      user: @user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end

  def test_returns_true_if_there_is_membership_entry_for_a_user_enterprise_team
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

    team = create :team, organization: @organization
    OrganizationMembershipEntry.create_entry(user: @organization_mixed_user, organization_id: @organization.id, adder_id: team.id, ability_id: 1, derived: true, adder_type: :enterprise_team)
    OrganizationMembershipEntry.create_entry(user: @organization_derived_user, organization_id: @organization.id, adder_id: team.id, ability_id: 2, derived: true, adder_type: :enterprise_team)

    assert OrganizationMembershipEntry.enterprise_team_managed?(
      user: @organization_mixed_user,
      organization_id: @organization.id,
      ability_id: 1
    )

    assert OrganizationMembershipEntry.enterprise_team_managed?(
      user: @organization_derived_user,
      organization_id: @organization.id,
      ability_id: 2
    )
  end

  def test_returns_false_if_there_is_no_membership_entry_for_a_explicit_user_enterprise_team
    refute OrganizationMembershipEntry.enterprise_team_managed?(
      user: @organization_explicit_user,
      organization_id: @organization.id,
      ability_id: 1
    )
  end
end

class SamlOrganizationMembershipEntryTest < GitHub::TestCase
  include OrganizationMembershipEntrySharedMethods
  include OrganizationMembershipEntryValidationSharedTests
  include OrganizationMembershipEntryCreateDerivedMembershipEntrySharedTests
  include OrganizationMembershipEntryCreateDerivedMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryCreateExplicitMembershipEntrySharedTests
  include OrganizationMembershipEntryRemoveDerivedMembershipEntrySharedTests
  include OrganizationMembershipEntryRemoveExplicitMembershipEntrySharedTests
  include OrganizationMembershipEntryExplicitSharedTests
  include OrganizationMembershipEntryDerivedSharedTests
  include OrganizationMembershipEntryRemoveEnterpriseTeamMembershipEntryEnterpriseTeamSharedTests
  include OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntrySharedTests
  include OrganizationMembershipEntryEnterpriseTeamSharedTests

  fixtures do
    @user = create :user
    @subject = ASubject.create
    @actor1 = AnActor.create
    @actor2 = AnActor.create
    @ability1 = @subject.grant @actor1, :read
    @ability2 = @subject.grant @actor2, :read

    @user_factory = :emu
    @organization_admin = create :emu
    @business = @organization_admin.enterprise_managed_business

    @organization = create :organization, business: @business, admin: @organization_admin
    @another_organization = create :organization, business: @business, admin: @organization_admin

    @organization_mixed_user = create :emu, business: @business
    @organization_explicit_user = create :emu, business: @business
    @organization_derived_user = create :emu, business: @business
    @organization_derived_user2 = create :emu, business: @business
  end

  setup do
    setup_test
  end
end unless GitHub.single_business_environment?

class OIDCOrganizationMembershipEntryTest < GitHub::TestCase
  include OrganizationMembershipEntrySharedMethods
  include OrganizationMembershipEntryValidationSharedTests
  include OrganizationMembershipEntryCreateDerivedMembershipEntrySharedTests
  include OrganizationMembershipEntryCreateDerivedMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryCreateExplicitMembershipEntrySharedTests
  include OrganizationMembershipEntryCreateExplicitMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryRemoveDerivedMembershipEntrySharedTests
  include OrganizationMembershipEntryRemoveExplicitMembershipEntrySharedTests
  include OrganizationMembershipEntryExplicitSharedTests
  include OrganizationMembershipEntryDerivedSharedTests
  include OrganizationMembershipEntryRemoveEnterpriseTeamMembershipEntryEnterpriseTeamSharedTests
  include OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntrySharedTests
  include OrganizationMembershipEntryEnterpriseTeamSharedTests

  fixtures do
    @user = create :user
    @subject = ASubject.create
    @actor1 = AnActor.create
    @actor2 = AnActor.create
    @ability1 = @subject.grant @actor1, :read
    @ability2 = @subject.grant @actor2, :read

    @user_factory = :emu
    @organization_admin = create :emu, provider_type: :oidc
    @business = @organization_admin.enterprise_managed_business

    @organization = create :organization, business: @business, admin: @organization_admin
    @another_organization = create :organization, business: @business, admin: @organization_admin

    @organization_mixed_user = create :emu, business: @business
    @organization_explicit_user = create :emu, business: @business
    @organization_derived_user = create :emu, business: @business
    @organization_derived_user2 = create :emu, business: @business
  end

  setup do
    setup_test
  end
end unless GitHub.single_business_environment?

class GHESWithSCIMOrganizationMembershipEntryTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include OrganizationMembershipEntrySharedMethods
  include OrganizationMembershipEntryValidationSharedTests
  include OrganizationMembershipEntryCreateDerivedMembershipEntrySharedTests
  include OrganizationMembershipEntryCreateDerivedMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryCreateExplicitMembershipEntrySharedTests
  include OrganizationMembershipEntryCreateExplicitMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryRemoveDerivedMembershipEntrySharedTests
  include OrganizationMembershipEntryRemoveExplicitMembershipEntrySharedTests
  include OrganizationMembershipEntryExplicitSharedTests
  include OrganizationMembershipEntryDerivedSharedTests
  include OrganizationMembershipEntryRemoveEnterpriseTeamMembershipEntryEnterpriseTeamSharedTests
  include OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntryBulkSharedTests
  include OrganizationMembershipEntryCreateEnterpriseTeamMembershipEntrySharedTests
  include OrganizationMembershipEntryEnterpriseTeamSharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @user = create :user
    @subject = ASubject.create
    @actor1 = AnActor.create
    @actor2 = AnActor.create
    @ability1 = @subject.grant @actor1, :read
    @ability2 = @subject.grant @actor2, :read

    @user_factory = :ghes_scim_user
    @business = create(:global_business)
    @organization_admin = create :ghes_scim_user, :admin, business: @business
    @business.saml_provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")

    @organization = create :organization, business: @business, admin: @organization_admin
    @another_organization = create :organization, business: @business, admin: @organization_admin

    @organization_mixed_user = create :ghes_scim_user, business: @business
    @organization_explicit_user = create :ghes_scim_user, business: @business
    @organization_derived_user = create :ghes_scim_user, business: @business
    @organization_derived_user2 = create :ghes_scim_user, business: @business
  end

  setup do
    setup_test
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
