# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/ability_models"

class AbilityActorTest < GitHub::TestCase
  test "list abilities" do
    actor = AnActor.create
    subject = ASubject.create
    connector = AnActorAndSubject.create

    subject.grant connector, :read
    connector.grant actor, :read

    info = <<-STR
      Inspecting actor abilities #{actor.abilities.map(&:inspect)}
      Inspecting Permissions #{Permission.all.map(&:inspect)}
      Inspecting Abilities #{Ability.all.map(&:inspect)}
      Constant is #{Permissions::QueryRouter::ACTOR_TYPES_WITH_FINE_GRAINED_PERMISSIONS}
    STR

    assert_same_elements [connector, subject], actor.abilities.map(&:subject), info

    indirect = actor.abilities.detect { |g| g.subject == subject }
    assert indirect.created_at, "includes a created_at timestamp"
    assert indirect.updated_at, "includes an updated_at timestamp"
  end
end
