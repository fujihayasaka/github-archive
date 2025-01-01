# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableTest < GitHub::TestCase
  test "#saving? returns true if no Restorable::TypeState exists for types" do
    restorable = Restorable.create
    assert restorable.saving?(:restorable_memberships), "saving? should be true"
  end

  test "#saving? returns false if Restorable::TypeState exists for types" do
    restorable = Restorable.create
    restorable.type_states.create({
      restorable_type: :restorable_memberships,
      state: :saved,
    })
    refute restorable.saving?(:restorable_memberships), "saving? should be false"
  end

  test "#saving? returns true if not all Restorable::TypeState exist for types" do
    restorable = Restorable.create
    restorable.type_states.create({
      restorable_type: :restorable_memberships,
      state: :saved,
    })
    assert restorable.saving?(:restorable_memberships, :restorable_repositories), "saving? should be false"
  end

  test "#saved creates Restorable::TypeState with state saved for type" do
    restorable = Restorable.create
    assert_equal true, restorable.saved(:restorable_memberships)
    type_state = restorable.type_states.first
    assert_predicate type_state, :present?
    assert_equal :saved, T.must(type_state).current_state
  end

  test "#saved? returns false if type state does not exist" do
    restorable = Restorable.create
    refute restorable.saved?(:restorable_memberships), "saved? should be false"
  end

  test "#saved? returns false if type state exists in a different state" do
    restorable = Restorable.create
    restorable.type_states.create(restorable_type: :restorable_memberships, state: :restored)
    assert_predicate restorable.type_states.first, :present?
    refute restorable.saved?(:restorable_memberships), "saved? should be false"
  end

  test "#saved? returns true if type state exists in saved state" do
    restorable = Restorable.create
    restorable.type_states.create(restorable_type: :restorable_memberships, state: :saved)
    assert restorable.saved?(:restorable_memberships), "saved? should be true"
  end

  test "#restoring updates existing Restorable::TypeState with state :saved to :restoring" do
    restorable = Restorable.create

    assert_difference("Restorable::TypeState.count", 1) do
      restorable.type_states.create(restorable_type: :restorable_memberships, state: :saved)
      assert_equal true, restorable.restoring(:restorable_memberships)
    end

    type_state = restorable.type_states.first
    assert_predicate type_state, :present?
    assert_equal :restoring, T.must(type_state).current_state
  end

  test "#restoring? returns false if type state does not exist" do
    restorable = Restorable.create
    refute restorable.restoring?(:restorable_memberships), "restoring? should be false"
  end

  test "#restoring? returns false if type state exists in a different state" do
    restorable = Restorable.create
    restorable.type_states.create(restorable_type: :restorable_memberships, state: :saved)
    assert_predicate restorable.type_states.first, :present?
    refute restorable.restoring?(:restorable_memberships), "restoring? should be false"
  end

  test "#restoring? returns true if type state exists in restoring state" do
    restorable = Restorable.create
    restorable.type_states.create(restorable_type: :restorable_memberships, state: :restoring)
    assert restorable.restoring?(:restorable_memberships), "restoring? should be true"
  end

  test "#restored updates existing Restorable::TypeState with state :restoring to :restored" do
    restorable = Restorable.create

    assert_difference("Restorable::TypeState.count", 1) do
      restorable.type_states.create(restorable_type: :restorable_memberships, state: :restoring)
      assert_equal true, restorable.restored(:restorable_memberships)
    end

    type_state = restorable.type_states.first
    assert_predicate type_state, :present?
    assert_equal :restored, T.must(type_state).current_state
  end

  test "#restored? returns false if type state does not exist" do
    restorable = Restorable.create
    refute restorable.restored?(:restorable_memberships), "restored? should be false"
  end

  test "#restored? returns false if type state exists in a different state" do
    restorable = Restorable.create
    restorable.type_states.create(restorable_type: :restorable_memberships, state: :restoring)
    assert_predicate restorable.type_states.first, :present?
    refute restorable.restored?(:restorable_memberships), "restored? should be false"
  end

  test "#restored? returns true if type state exists in restored state" do
    restorable = Restorable.create
    restorable.type_states.create(restorable_type: :restorable_memberships, state: :restored)
    assert restorable.restored?(:restorable_memberships), "restored? should be true"
  end
end
