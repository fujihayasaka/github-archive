# typed: strict
# frozen_string_literal: true

require "test_helper"

class Issues::Domain::LabelsTest < GitHub::TestCase
  sig { returns(Issues::Domain) }
  def domain
    Issues::Domain.new
  end

  context "#by_repository_and_normalized_ids" do
    test "finds a label when it exists in that repository" do
      repo = create(:repository)
      label = create(:label, name: "bug", repository: repo)

      assert_equal label, domain.labels.by_repository_and_normalized_ids(repository_id: repo.id, label_ids: [label.id]).first
    end

    test "does not find a label when it exists in a different repository" do
      label = create(:label)
      repo = create(:repository)

      assert_empty domain.labels.by_repository_and_normalized_ids(repository_id: repo.id, label_ids: [label.id])
    end

    test "doesn't find a label if it doesn't exist" do
      repo = create(:repository)

      assert_empty domain.labels.by_repository_and_normalized_ids(repository_id: repo.id, label_ids: ["1"])
    end
  end
end
