# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::TopicsTest < GitHub::TestCase

  fixtures do
    @topic1 = create :topic
    @topic2 = create :topic
  end

  setup do
    @domain = T.must(T.let(Repositories::Domain::Topics.new, T.nilable(Repositories::Domain::Topics)))
  end

  sig { returns(Repositories::Domain::Topics) }
  def domain
    @domain
  end

  context ".by_names" do
    test "returns topics by name" do
      assert_same_elements [@topic1, @topic2], domain.by_names(names: [@topic1.name, @topic2.name, "fakename"]).to_a
    end
  end
end
